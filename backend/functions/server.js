// --- IMPORTATION DES OUTILS (BIBLIOTHÈQUES) ---
// Express est le "moteur" qui nous permet de créer des routes d'API (comme une adresse web)
const express = require("express");
// CORS permet d'autoriser l'application mobile ou web à discuter avec ce serveur
const cors = require("cors");
// L'outil officiel de Google pour interagir avec Firebase (Authentification, Notifications)
const admin = require("firebase-admin");
// WebSocket permet une communication "en direct" (comme un chat) entre le serveur et l'appli
const WebSocket = require("ws");
// Module pour créer un serveur HTTP standard
const http = require("http");
// Permet de lire les fichiers de configuration secrets (.env)
const dotenv = require("dotenv");
// Axios permet au serveur d'appeler d'autres sites ou services web
const axios = require("axios");
// Multer sert à gérer l'envoi de fichiers (images, PDFs) depuis l'appli
const multer = require("multer");
// Outils mathématiques pour créer des codes secrets ou des identifiants uniques
const crypto = require("crypto");
// JWT (JSON Web Token) sert à créer des "laissez-passer" sécurisés
const jwt = require("jsonwebtoken");
// Crée des identifiants (ID) uniques et impossibles à deviner
const { v4: uuidv4 } = require("uuid");
const path = require("path");
const fs = require("fs");
// Le client pour discuter avec notre base de données Supabase
const { createClient } = require("@supabase/supabase-js");
// Client pour stocker des fichiers lourds sur Cloudflare R2 (comme un disque dur dans le cloud)
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} = require("@aws-sdk/client-s3");

// --- CONFIGURATION DE L'ENVIRONNEMENT ---
// On cherche un fichier .env.local ou .env qui contient nos clés secrètes
const envLocalPath = path.join(__dirname, ".env.local");
if (fs.existsSync(envLocalPath)) {
  dotenv.config({ path: envLocalPath });
} else {
  dotenv.config();
}

/**
 * Petite fonction pour transformer du texte JSON en objet informatique
 * Si ça rate, on renvoie une valeur par défaut
 */
function parseJsonEnv(value, fallback = null) {
  if (!value) return fallback;
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

/**
 * Nettoie et prépare la clé secrète de Firebase pour qu'elle soit lisible
 */
function sanitizeServiceAccount(raw) {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (parsed.private_key) {
      // Remplace les sauts de ligne écrits "\n" par de vrais retours à la ligne
      parsed.private_key = String(parsed.private_key).replace(/\\n/g, "\n");
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

// On récupère les identifiants de notre projet Firebase
const firebaseProjectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GCLOUD_PROJECT ||
  "up2school-app";
const firebaseServiceAccount = sanitizeServiceAccount(
  process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
);

// On initialise la connexion avec Google Firebase
if (!admin.apps.length) {
  const firebaseConfig = {
    projectId: firebaseProjectId,
  };

  if (firebaseServiceAccount) {
    firebaseConfig.credential = admin.credential.cert(firebaseServiceAccount);
  }

  admin.initializeApp(firebaseConfig);
}

// Initialisation de l'application Express
const app = express();
const server = http.createServer(app);
// Création d'un "canal" de communication en direct (WebSocket)
const wss = new WebSocket.Server({ server });
// Préparation de l'outil pour recevoir des fichiers en mémoire
const upload = multer({ storage: multer.memoryStorage() });
const auth = admin.auth();
// On garde en mémoire les utilisateurs connectés en direct
const clients = new Map();

// --- LISTE DES TABLES DE LA BASE DE DONNÉES ---
const TABLES = {
  users: "user_profiles",
  files: "files",
  events: "events",
  ads: "ads",
  notifications: "notifications",
  faculties: "faculties",
  payments: "payment_transactions",
  history: "activity_history",
};

// --- CONNEXION À SUPABASE (NOTRE BASE DE DONNÉES) ---
const supabaseProjectRef =
  process.env.SUPABASE_PROJECT_ID || process.env.SUPABASE_PROJECT_REF;
const supabaseUrl =
  process.env.SUPABASE_URL ||
  (supabaseProjectRef ? `https://${supabaseProjectRef}.supabase.co` : null);
const supabaseServiceRoleKey =
  process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE;

const supabase =
  supabaseUrl && supabaseServiceRoleKey
    ? createClient(supabaseUrl, supabaseServiceRoleKey, {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
        realtime: {
          websocket: WebSocket,
        },
      })
    : null;

// --- CONFIGURATION DU STOCKAGE (CLOUDFLARE R2) ---
function deriveR2BucketName() {
  if (process.env.R2_BUCKET) return process.env.R2_BUCKET;
  if (process.env.CLOUDFLARE_R2_BUCKET) return process.env.CLOUDFLARE_R2_BUCKET;

  const s3Api =
    process.env.R2_S3_API_URL || process.env.CLOUDFLARE_R2_S3_API_URL;
  if (!s3Api) return null;

  try {
    const parsed = new URL(s3Api);
    const parts = parsed.pathname.split("/").filter(Boolean);
    return parts[0] || null;
  } catch (_) {
    return null;
  }
}

const r2BucketName = deriveR2BucketName();
const r2Endpoint =
  process.env.R2_ENDPOINT ||
  process.env.CLOUDFLARE_R2_ENDPOINT ||
  (process.env.CLOUDFLARE_ACCOUNT_ID
    ? `https://${process.env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`
    : null);
const r2AccessKeyId =
  process.env.R2_ACCESS_KEY_ID || process.env.CLOUDFLARE_R2_ACCESS_KEY_ID;
const r2SecretAccessKey =
  process.env.R2_SECRET_ACCESS_KEY ||
  process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY;

const r2Client =
  r2Endpoint && r2AccessKeyId && r2SecretAccessKey
    ? new S3Client({
        region: "auto",
        endpoint: r2Endpoint,
        credentials: {
          accessKeyId: r2AccessKeyId,
          secretAccessKey: r2SecretAccessKey,
        },
      })
    : null;

// On autorise toutes les connexions (CORS) et on définit la taille max des messages (20 Mo)
app.use(
  cors({
    origin: true,
    credentials: true,
  }),
);
app.use(express.json({ limit: "20mb" }));
app.use(express.urlencoded({ extended: true }));

/**
 * Vérifie si Supabase est bien allumé, sinon on arrête tout avec un message d'erreur
 */
function ensureSupabase() {
  if (!supabase) {
    throw new Error(
      "Supabase is not configured. Define SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.",
    );
  }
  return supabase;
}

/**
 * Vérifie si le stockage R2 est bien allumé
 */
function ensureR2() {
  if (!r2Client || !r2BucketName) {
    throw new Error(
      "Cloudflare R2 is not configured. Define R2 endpoint, access key, secret key and bucket.",
    );
  }
  return {
    client: r2Client,
    bucket: r2BucketName,
  };
}

/**
 * Détermine l'adresse du serveur (pour savoir comment s'appeler soi-même)
 */
function resolveBaseUrl(req) {
  return process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get("host")}`;
}

/**
 * Donne l'heure actuelle au format universel (ISO)
 */
function nowIso() {
  return new Date().toISOString();
}

/**
 * Tente de transformer n'importe quel format de date en objet Date JavaScript
 */
function parseDateValue(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "number") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (value && typeof value.toDate === "function") {
    return value.toDate();
  }
  if (value && typeof value._seconds === "number") {
    return new Date(value._seconds * 1000);
  }
  return null;
}

/**
 * Transforme une date en texte ISO, ou donne l'heure de maintenant si la date est invalide
 */
function parseIsoOrNow(value) {
  return parseDateValue(value)?.toISOString() || nowIso();
}

/**
 * Uniformise les dates pour la base de données
 */
function normalizeTimestamp(value) {
  return parseDateValue(value)?.toISOString() || null;
}

/**
 * Nettoie un texte pour enlever les espaces inutiles au début et à la fin
 */
function normalizeString(value, fallback = "") {
  return typeof value === "string" ? value.trim() : fallback;
}

function normalizeComparableString(value) {
  return normalizeString(value).toLowerCase();
}

function normalizeDocumentType(value) {
  const normalized = normalizeComparableString(value)
    .replace(/[’`]/g, "'")
    .replace(/\s+/g, " ");

  switch (normalized) {
    case "cours":
      return "cours";
    case "td":
    case "travaux diriges":
    case "travaux dirigés":
      return "td";
    case "sujet":
    case "sujets":
    case "sujet d'examen":
    case "sujets d'examen":
    case "examen":
    case "examens":
      return "sujets";
    case "projet":
    case "projets":
      return "projets";
    case "autre":
    case "autres":
    case "autre ressource":
    case "autres ressources":
      return "autres";
    default:
      return normalized;
  }
}

function academicScopeMatches(row, user) {
  const faculty = normalizeComparableString(user?.faculty);
  const level = normalizeComparableString(user?.level);
  const field = normalizeComparableString(user?.field);
  if (!faculty || !level || !field) return false;

  return (
    normalizeComparableString(row?.faculty) === faculty &&
    normalizeComparableString(row?.level) === level &&
    normalizeComparableString(row?.field) === field
  );
}

function isWithinDelegateFileDeleteWindow(row, referenceDate = new Date()) {
  const uploadedAt =
    parseDateValue(row?.uploaded_at || row?.uploadedAt) ||
    parseDateValue(row?.publish_date || row?.publishDate) ||
    parseDateValue(row?.created_at || row?.createdAt);

  if (!uploadedAt) return false;

  const ageMs = referenceDate.getTime() - uploadedAt.getTime();
  if (ageMs < 0) return true;

  return ageMs <= 15 * 24 * 60 * 60 * 1000;
}

function canDeleteFile(row, user, userId) {
  const role = normalizeRole(user?.role);
  const isAdmin = role === "admin";
  const isOwner =
    row?.uploaded_by === userId ||
    row?.uploaded_by === user?.id ||
    row?.uploaded_by === user?.email;
  const isDelegateInScope =
    role === "delegate" &&
    academicScopeMatches(row, user) &&
    isWithinDelegateFileDeleteWindow(row);

  return isAdmin || isOwner || isDelegateInScope;
}

/**
 * Transforme n'importe quoi en une liste de textes propre
 */
function normalizeStringArray(value) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item)).filter(Boolean);
}

/**
 * S'assure qu'on travaille bien avec un objet (dictionnaire)
 */
function normalizeObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return value;
}

/**
 * Vérifie que le rôle de l'utilisateur est bien l'un des rôles autorisés
 * Si c'est n'importe quoi d'autre, on met "student" par défaut
 */
function normalizeRole(value) {
  const normalized = String(value || "student").toLowerCase();
  return ["admin", "delegate", "guest", "student"].includes(normalized)
    ? normalized
    : "student";
}

/**
 * Récupère la clé secrète pour signer les jetons d'accès aux fichiers
 */
function buildDownloadTokenSecret() {
  return (
    process.env.FILE_ACCESS_TOKEN_SECRET ||
    process.env.JWT_SECRET ||
    `${firebaseProjectId}-file-access`
  );
}

/**
 * Récupère la clé API de Firebase (nécessaire pour l'authentification)
 */
function getFirebaseApiKey() {
  const apiKey = process.env.API_KEY || process.env.FIREBASE_API_KEY;
  if (!apiKey) {
    throw new Error("API_KEY or FIREBASE_API_KEY is required");
  }
  return apiKey;
}

/**
 * Traduit les codes d'erreurs bizarres de Firebase en messages simples et en français
 */
function extractFirebaseAuthError(error, fallback = "Authentication failed") {
  const providerMessage = String(
    error?.response?.data?.error?.message || error?.message || "",
  ).toUpperCase();

  switch (providerMessage) {
    case "INVALID_LOGIN_CREDENTIALS":
    case "INVALID_PASSWORD":
      return {
        status: 401,
        message: "Mot de passe incorrect",
      };
    case "EMAIL_NOT_FOUND":
    case "USER_NOT_FOUND":
      return {
        status: 401,
        message: "Aucun compte Firebase trouve pour cet email",
      };
    case "INVALID_EMAIL":
      return {
        status: 400,
        message: "Adresse email invalide",
      };
    case "TOO_MANY_ATTEMPTS_TRY_LATER":
      return {
        status: 429,
        message: "Trop de tentatives. Reessayez plus tard",
      };
    case "INVALID_REFRESH_TOKEN":
    case "TOKEN_EXPIRED":
    case "USER_DISABLED":
      return {
        status: 401,
        message: "Session expirée. Reconnectez-vous",
      };
    default:
      return {
        status: 500,
        message: fallback,
      };
  }
}

/**
 * Récupère le prix de l'abonnement configuré (par défaut 350 XOF)
 */
function getSubscriptionAmount() {
  const amount = Number(process.env.UP2SCHOOL_SUBSCRIPTION_AMOUNT || 350);
  if (!Number.isFinite(amount) || amount <= 0 || amount % 5 !== 0) {
    throw new Error(
      "UP2SCHOOL_SUBSCRIPTION_AMOUNT must be a positive multiple of 5",
    );
  }
  return amount;
}

/**
 * Vérifie que les identifiants pour le paiement sont bien là
 */
function getPaiementProConfig() {
  const merchantId = process.env.PAIEMENT_PRO_MERCHANT_ID;
  if (!merchantId) {
    throw new Error("PAIEMENT_PRO_MERCHANT_ID is required");
  }
  return {
    merchantId,
  };
}

/**
 * Calcule quand a commencé l'année scolaire actuelle (en général le 1er juillet)
 */
function getCurrentSchoolYearStart(referenceDate = new Date()) {
  const year =
    referenceDate.getUTCMonth() >= 6
      ? referenceDate.getUTCFullYear()
      : referenceDate.getUTCFullYear() - 1;
  return new Date(Date.UTC(year, 6, 1, 0, 0, 0, 0));
}

/**
 * Calcule quand se termine l'année scolaire actuelle
 */
function getNextSchoolYearBoundary(referenceDate = new Date()) {
  const schoolYearStart = getCurrentSchoolYearStart(referenceDate);
  return new Date(
    Date.UTC(schoolYearStart.getUTCFullYear() + 1, 6, 1, 0, 0, 0, 0),
  );
}

/**
 * Crée une étiquette pour l'année scolaire (ex: "2023-2024")
 */
function getSchoolYearLabel(referenceDate = new Date()) {
  const startYear = getCurrentSchoolYearStart(referenceDate).getUTCFullYear();
  return `${startYear}-${startYear + 1}`;
}

/**
 * Crée un jeton (token) qui permet de télécharger un fichier pendant une courte durée
 */
function signStorageAccessToken({ storagePath, userId, expiresIn = "20m" }) {
  return jwt.sign(
    {
      storagePath,
      userId,
      type: "file_access",
    },
    buildDownloadTokenSecret(),
    { expiresIn },
  );
}

/**
 * Vérifie si un jeton de téléchargement est encore valide
 */
function verifyStorageAccessToken(token, storagePath) {
  try {
    const decoded = jwt.verify(token, buildDownloadTokenSecret());
    return decoded?.storagePath === storagePath ? decoded : null;
  } catch (_) {
    return null;
  }
}

/**
 * Encode un texte pour qu'il puisse être utilisé dans un "Topic" de notification (sans caractères interdits)
 */
function encodeTopicSegment(value) {
  if (!value) return "";
  return Buffer.from(String(value).trim(), "utf8")
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

/**
 * Détermine le "Topic" (le canal) pour envoyer des notifications d'événements
 * Si c'est global, tout le monde reçoit. Sinon, seulement la bonne filière/niveau.
 */
function getTopicForEvent(eventData) {
  if (eventData?.isGlobal) {
    return "events_global";
  }

  const faculty = encodeTopicSegment(eventData?.faculty);
  const level = encodeTopicSegment(eventData?.level);
  const field = encodeTopicSegment(eventData?.field);
  if (!faculty || !level || !field) return "";
  return `faculte_${faculty}_niveau_${level}_filiere_${field}`;
}

/**
 * Détermine le "Topic" pour les publicités
 */
function getTopicForAd(adData) {
  if (adData?.isGlobal) {
    return "ads_global";
  }

  const faculty = encodeTopicSegment(adData?.faculty);
  const level = encodeTopicSegment(adData?.level);
  const field = encodeTopicSegment(adData?.field);
  if (!faculty || !level || !field) return "";
  return `faculte_${faculty}_niveau_${level}_filiere_${field}`;
}

/**
 * Détermine le "Topic" pour les nouveaux fichiers
 */
function getTopicForFile(fileData) {
  const faculty = encodeTopicSegment(fileData?.faculty);
  const level = encodeTopicSegment(fileData?.level);
  const field = encodeTopicSegment(fileData?.field);
  if (!faculty || !level || !field) return "";
  return `faculte_${faculty}_niveau_${level}_filiere_${field}`;
}

/**
 * Construit l'URL (le lien) pour télécharger un fichier en passant par notre serveur proxy
 */
function buildStorageProxyUrl(req, storagePath, fileName, options = {}) {
  const encoded = encodeURIComponent(storagePath);
  const params = new URLSearchParams();
  params.set("name", fileName || storagePath.split("/").pop() || "file");
  if (options.accessToken) {
    params.set("access_token", options.accessToken);
  }
  return `${resolveBaseUrl(req)}/api/storage/object/${encoded}?${params.toString()}`;
}

/**
 * Analyse une adresse URL pour en extraire le chemin interne du fichier
 */
function extractStoragePathFromUrl(url) {
  if (!url || typeof url !== "string") return null;

  try {
    const parsed = new URL(url);

    // Cas de notre propre serveur proxy
    if (parsed.pathname.startsWith("/api/storage/object/")) {
      return decodeURIComponent(
        parsed.pathname.replace("/api/storage/object/", ""),
      );
    }

    // Cas de l'ancien stockage Firebase
    if (parsed.hostname.includes("firebasestorage.googleapis.com")) {
      const match = parsed.pathname.match(/\/o\/(.+)$/);
      if (match) {
        return decodeURIComponent(match[1]);
      }
    }

    // Cas du stockage Cloudflare R2
    if (parsed.hostname.includes("cloudflarestorage.com")) {
      const parts = parsed.pathname.split("/").filter(Boolean);
      if (parts.length === 0) return null;
      if (parts[0] === r2BucketName) {
        parts.shift();
      }
      return parts.join("/");
    }
  } catch (_) {
    return null;
  }

  return null;
}

/**
 * Résume l'état de l'abonnement d'un utilisateur à un instant T
 */
function buildSubscriptionSnapshot(userData, referenceDate = new Date()) {
  const subscriptionStartDate = parseDateValue(
    userData?.subscription_start_date || userData?.subscriptionStartDate,
  );
  const subscriptionEndDate = parseDateValue(
    userData?.subscription_end_date || userData?.subscriptionEndDate,
  );

  // Un abonnement est actif si le bouton "souscrit" est coché ET si la date de fin n'est pas passée
  const hasActiveSubscription =
    Boolean(userData?.subscribed) &&
    Boolean(subscriptionEndDate) &&
    subscriptionEndDate.getTime() > referenceDate.getTime();

  return {
    subscribed: hasActiveSubscription,
    hasActiveSubscription,
    subscriptionStatus: hasActiveSubscription ? "active" : "inactive",
    subscriptionStartDate: subscriptionStartDate?.toISOString() || null,
    subscriptionEndDate: subscriptionEndDate?.toISOString() || null,
    subscriptionSchoolYear:
      userData?.subscription_school_year ||
      userData?.subscriptionSchoolYear ||
      (subscriptionEndDate ? getSchoolYearLabel(subscriptionEndDate) : null),
    lastSubscriptionTransactionId:
      userData?.last_subscription_transaction_id ||
      userData?.lastSubscriptionTransactionId ||
      null,
  };
}

/**
 * Calcule si un utilisateur a le droit de lire un fichier spécifique
 */
function buildFileAccess(userData, fileData, referenceDate = new Date()) {
  const publishDate =
    parseDateValue(fileData?.publish_date || fileData?.publishDate) ||
    parseDateValue(fileData?.uploaded_at || fileData?.uploadedAt) ||
    parseDateValue(fileData?.created_at || fileData?.createdAt) ||
    referenceDate;

  const currentSchoolYearStart = getCurrentSchoolYearStart(referenceDate);
  const subscription = buildSubscriptionSnapshot(userData, referenceDate);
  const role = String(userData?.role || "").toLowerCase();
  
  // Les admins et délégués sont des "VIP"
  const isPrivilegedUser = ["admin", "delegate"].includes(role);
  // Un fichier est "vieux" s'il a été publié avant le début de l'année scolaire actuelle
  const isOldFile = publishDate.getTime() < currentSchoolYearStart.getTime();
  
  // On peut accéder au fichier si :
  // - Ce n'est pas un vieux fichier
  // - OU si on est un VIP
  // - OU si on a payé l'abonnement
  const canAccess =
    !isOldFile || isPrivilegedUser || subscription.hasActiveSubscription;

  return {
    canAccess,
    isOldFile,
    isPremiumLocked: isOldFile && !canAccess,
    publishDate: publishDate.toISOString(),
    currentSchoolYearStart: currentSchoolYearStart.toISOString(),
    accessDeniedReason:
      !canAccess && isOldFile
        ? "subscription_required_for_archived_file"
        : null,
  };
}

/**
 * Prépare les données d'un utilisateur pour les envoyer à l'application mobile
 */
function userResponse(row) {
  const subscription = buildSubscriptionSnapshot(row);
  return {
    id: row.id,
    email: row.email || "",
    name: row.name || "",
    phone: row.phone || "",
    role: normalizeRole(row.role),
    faculty: row.faculty || "",
    level: row.level || "",
    field: row.field || "",
    createdAt: normalizeTimestamp(row.created_at) || nowIso(),
    updatedAt: normalizeTimestamp(row.updated_at),
    lastActivity: normalizeTimestamp(row.last_activity),
    devices: Array.isArray(row.devices) ? row.devices : [],
    pushTokens: Array.isArray(row.push_tokens) ? row.push_tokens : [],
    subscribed: subscription.subscribed,
    subscriptionStartDate: subscription.subscriptionStartDate,
    subscriptionEndDate: subscription.subscriptionEndDate,
    subscriptionSchoolYear: subscription.subscriptionSchoolYear,
    lastSubscriptionTransactionId: subscription.lastSubscriptionTransactionId,
    hasActiveSubscription: subscription.hasActiveSubscription,
    subscriptionStatus: subscription.subscriptionStatus,
  };
}

/**
 * Prépare les données d'un fichier pour l'application mobile
 */
function fileResponse(req, row, options = {}) {
  const storagePath = row.storage_path || extractStoragePathFromUrl(row.url);
  const access = buildFileAccess(options.user, row);
  // On génère un ticket de téléchargement temporaire si l'utilisateur a le droit
  const accessToken =
    storagePath && access.canAccess && options.user?.id
      ? signStorageAccessToken({
          storagePath,
          userId: options.user.id,
        })
      : null;

  return {
    id: row.id,
    name: row.name || "",
    url: storagePath
      ? access.canAccess
        ? buildStorageProxyUrl(req, storagePath, row.file_name || row.name, {
            accessToken,
          })
        : ""
      : row.url || "",
    fileName: row.file_name || "",
    fileType: row.file_type || "",
    faculty: row.faculty || "",
    level: row.level || "",
    field: row.field || "",
    unit: row.unit || "",
    type: row.type || "",
    size: row.size || null,
    uploadedAt: normalizeTimestamp(row.uploaded_at) || nowIso(),
    publishDate: access.publishDate,
    uploadedBy: row.uploaded_by || "",
    favorites: Array.isArray(row.favorites) ? row.favorites : [],
    viewedBy: Array.isArray(row.viewed_by) ? row.viewed_by : [],
    downloadCount: Number(row.download_count || 0),
    view_count: Number(row.view_count || 0),
    readingProgress: normalizeObject(row.reading_progress),
    lastOpened: normalizeTimestamp(row.last_opened),
    canAccess: access.canAccess,
    isOldFile: access.isOldFile,
    isPremiumLocked: access.isPremiumLocked,
    accessDeniedReason: access.accessDeniedReason,
    currentSchoolYearStart: access.currentSchoolYearStart,
    storagePath,
    createdAt: normalizeTimestamp(row.created_at),
    updatedAt: normalizeTimestamp(row.updated_at),
  };
}

/**
 * Prépare les données d'un événement
 */
function eventResponse(row) {
  return {
    id: row.id,
    title: row.title || "",
    description: row.description || "",
    date: normalizeTimestamp(row.date) || nowIso(),
    location: row.location || "",
    faculty: row.faculty || "",
    level: row.level || "",
    field: row.field || "",
    createdBy: row.created_by || "",
    createdAt: normalizeTimestamp(row.created_at) || nowIso(),
    imageUrls: Array.isArray(row.image_urls) ? row.image_urls : [],
    isGlobal: Boolean(row.is_global),
    reminder48hSent: Boolean(row.reminder_48h_sent),
    reminder12hSent: Boolean(row.reminder_12h_sent),
    notificationSent: Boolean(row.notification_sent),
  };
}

/**
 * Prépare les données d'une faculté (filière)
 */
function facultyResponse(row) {
  return {
    id: row.id,
    name: row.name || "",
    levels: Array.isArray(row.levels) ? row.levels : [],
    fields: normalizeObject(row.fields),
    units: normalizeObject(row.units),
    createdAt: normalizeTimestamp(row.created_at),
    updatedAt: normalizeTimestamp(row.updated_at),
  };
}

/**
 * Prépare les données d'une publicité
 */
function adResponse(req, row) {
  const rawImageUrl = row.image_url || "";
  const usesFirebaseStorageUrl =
    typeof rawImageUrl === "string" &&
    rawImageUrl.includes("firebasestorage.googleapis.com");
  const storagePath = row.storage_path || null;

  let imageUrl = rawImageUrl;
  if (storagePath) {
    imageUrl = buildStorageProxyUrl(req, storagePath, `${row.id}.jpg`);
  } else if (!usesFirebaseStorageUrl && !imageUrl) {
    const derivedStoragePath = extractStoragePathFromUrl(rawImageUrl);
    if (derivedStoragePath) {
      imageUrl = buildStorageProxyUrl(req, derivedStoragePath, `${row.id}.jpg`);
    }
  }

  return {
    id: row.id,
    title: row.title || "",
    description: row.description || "",
    imageUrl,
    targetUrl: row.target_url || "",
    faculty: row.faculty || "",
    level: row.level || "",
    field: row.field || "",
    isGlobal: Boolean(row.is_global),
    isActive: row.is_active !== false,
    clicks: Number(row.clicks || 0),
    startDate: normalizeTimestamp(row.start_date),
    endDate: normalizeTimestamp(row.end_date),
    createdAt: normalizeTimestamp(row.created_at),
    storagePath: storagePath || extractStoragePathFromUrl(rawImageUrl),
  };
}

/**
 * Prépare les données d'une notification
 */
function notificationResponse(row) {
  return {
    id: row.id,
    type: row.type || "",
    title: row.title || "",
    body: row.body || "",
    userId: row.user_id || "",
    read: Boolean(row.read),
    timestamp: normalizeTimestamp(row.timestamp) || nowIso(),
    readAt: normalizeTimestamp(row.read_at),
    ...normalizeObject(row.data),
  };
}

/**
 * Prépare les données d'un paiement
 */
function paymentResponse(row) {
  return {
    id: row.id,
    provider: row.provider,
    type: row.type,
    planCode: row.plan_code,
    userId: row.user_id,
    amount: row.amount,
    currency: row.currency,
    status: row.status,
    cinetpayStatus: row.cinetpay_status,
    customerName: row.customer_name,
    customerPhoneNumber: row.customer_phone_number,
    metadata: row.metadata,
    schoolYearLabel: row.school_year_label,
    verificationCode: row.verification_code,
    verificationMessage: row.verification_message,
    paymentMethod: row.payment_method,
    operatorId: row.operator_id,
    paymentDate: normalizeTimestamp(row.payment_date),
    verifiedAt: normalizeTimestamp(row.verified_at),
    fulfilledAt: normalizeTimestamp(row.fulfilled_at),
    createdAt: normalizeTimestamp(row.created_at),
    updatedAt: normalizeTimestamp(row.updated_at),
    checkoutCode: row.checkout_code,
    checkoutMessage: row.checkout_message,
    paymentUrl: row.payment_url,
    providerResponse: row.provider_response,
    webhookPayload: row.webhook_payload,
    subscriptionStartDate: normalizeTimestamp(row.subscription_start_date),
    subscriptionEndDate: normalizeTimestamp(row.subscription_end_date),
    subscriptionSchoolYear: row.subscription_school_year,
  };
}

/**
 * Transforme les données reçues de l'application en une "ligne" prête pour la table USERS de Supabase
 */
function toUserRow(payload, base = {}) {
  const merged = { ...base, ...payload };
  return {
    id: merged.id || base.id,
    email: normalizeString(merged.email, base.email || ""),
    name: normalizeString(merged.name, base.name || ""),
    phone: normalizeString(merged.phone, base.phone || ""),
    role: normalizeRole(merged.role || base.role || "student"),
    faculty: normalizeString(merged.faculty, base.faculty || ""),
    level: normalizeString(merged.level, base.level || ""),
    field: normalizeString(merged.field, base.field || ""),
    created_at: parseIsoOrNow(
      merged.createdAt || base.created_at || base.createdAt,
    ),
    updated_at: nowIso(),
    last_activity: parseIsoOrNow(
      merged.lastActivity || merged.last_activity || base.last_activity,
    ),
    devices: Array.isArray(merged.devices)
      ? merged.devices
      : base.devices || [],
    push_tokens: Array.isArray(merged.pushTokens)
      ? merged.pushTokens
      : Array.isArray(merged.push_tokens)
        ? merged.push_tokens
        : base.push_tokens || [],
    subscribed: Boolean(merged.subscribed || base.subscribed || false),
    subscription_start_date:
      normalizeTimestamp(
        merged.subscriptionStartDate ||
          merged.subscription_start_date ||
          base.subscription_start_date,
      ) || null,
    subscription_end_date:
      normalizeTimestamp(
        merged.subscriptionEndDate ||
          merged.subscription_end_date ||
          base.subscription_end_date,
      ) || null,
    subscription_school_year:
      merged.subscriptionSchoolYear ||
      merged.subscription_school_year ||
      base.subscription_school_year ||
      null,
    last_subscription_transaction_id:
      merged.lastSubscriptionTransactionId ||
      merged.last_subscription_transaction_id ||
      base.last_subscription_transaction_id ||
      null,
  };
}

/**
 * Prépare une ligne pour la table FILES (Fichiers)
 */
function toFileRow(payload, userId) {
  const storagePath =
    payload.storagePath || extractStoragePathFromUrl(payload.url);
  return {
    id: payload.id || `file_${Date.now()}`,
    name: normalizeString(payload.name),
    url: storagePath ? "" : normalizeString(payload.url),
    file_name: normalizeString(payload.fileName),
    file_type: normalizeString(payload.fileType),
    faculty: normalizeString(payload.faculty),
    level: normalizeString(payload.level),
    field: normalizeString(payload.field),
    unit: normalizeString(payload.unit),
    type: normalizeDocumentType(payload.type),
    size: payload.size || null,
    uploaded_at: parseIsoOrNow(payload.uploadedAt),
    publish_date: parseIsoOrNow(payload.publishDate || payload.uploadedAt),
    uploaded_by: userId,
    favorites: Array.isArray(payload.favorites) ? payload.favorites : [],
    viewed_by: Array.isArray(payload.viewedBy) ? payload.viewedBy : [],
    download_count: Number(payload.downloadCount || 0),
    view_count: Number(payload.viewCount || 0),
    reading_progress: normalizeObject(payload.readingProgress),
    last_opened: normalizeTimestamp(payload.lastOpened),
    storage_path: storagePath || null,
    created_at: parseIsoOrNow(payload.createdAt),
    updated_at: nowIso(),
  };
}

/**
 * Prépare une ligne pour la table EVENTS (Événements)
 */
function toEventRow(payload, userId) {
  return {
    id: payload.id || `event_${Date.now()}`,
    title: normalizeString(payload.title),
    description: normalizeString(payload.description),
    date: parseIsoOrNow(payload.date),
    location: normalizeString(payload.location),
    faculty: normalizeString(payload.faculty),
    level: normalizeString(payload.level),
    field: normalizeString(payload.field),

    created_by: userId,
    created_at: parseIsoOrNow(payload.createdAt),
    image_urls: Array.isArray(payload.imageUrls) ? payload.imageUrls : [],
    is_global: Boolean(payload.isGlobal),
    reminder_48h_sent: Boolean(payload.reminder48hSent),
    reminder_12h_sent: Boolean(payload.reminder12hSent),
    notification_sent: Boolean(payload.notificationSent),
  };
}

/**
 * Prépare une ligne pour la table ADS (Publicités)
 */
function toAdRow(payload, userId) {
  const storagePath =
    payload.storagePath || extractStoragePathFromUrl(payload.imageUrl);
  const isGlobal = Boolean(payload.isGlobal);
  return {
    id: payload.id || `ad_${Date.now()}`,
    title: normalizeString(payload.title),
    description: normalizeString(payload.description),
    image_url: storagePath ? "" : normalizeString(payload.imageUrl),
    storage_path: storagePath || null,
    target_url: normalizeString(payload.targetUrl),
    faculty: isGlobal ? "" : normalizeString(payload.faculty),
    level: isGlobal ? "" : normalizeString(payload.level),
    field: isGlobal ? "" : normalizeString(payload.field),
    is_global: isGlobal,
    is_active: payload.isActive !== false,
    clicks: Number(payload.clicks || 0),
    start_date: parseIsoOrNow(payload.startDate),
    end_date: normalizeTimestamp(payload.endDate)
      ? parseIsoOrNow(payload.endDate)
      : new Date(Date.now() + 7 * 86400000).toISOString(),
    created_by: userId,
    created_at: nowIso(),
  };
}

/**
 * Vérifie si les données d'une publicité sont complètes et correctes
 */
function validateAdPayload(payload) {
  const title = normalizeString(payload?.title);
  const targetUrl = normalizeString(payload?.targetUrl);
  const imageUrl = normalizeString(payload?.imageUrl);
  const storagePath = normalizeString(payload?.storagePath);
  const startDate = parseDateValue(payload?.startDate);
  const endDate = parseDateValue(payload?.endDate);
  const isGlobal = payload?.isGlobal === true || payload?.isGlobal === "true";
  const faculty = normalizeString(payload?.faculty);
  const level = normalizeString(payload?.level);
  const field = normalizeString(payload?.field);

  if (!title) {
    return "title is required";
  }
  if (!targetUrl) {
    return "targetUrl is required";
  }
  if (!imageUrl && !storagePath) {
    return "imageUrl is required";
  }
  if (!startDate) {
    return "startDate is required";
  }
  if (!endDate) {
    return "endDate is required";
  }
  if (endDate < startDate) {
    return "endDate must be after startDate";
  }
  if (!isGlobal && (!faculty || !level || !field)) {
    return "faculty, level and field are required for a targeted ad";
  }

  return null;
}

/**
 * Exécute une requête Supabase et gère le cas où aucun résultat n'est trouvé
 */
async function supabaseMaybeSingle(query) {
  const { data, error } = await query.maybeSingle();
  if (error && error.code !== "PGRST116") {
    throw error;
  }
  return data || null;
}

/**
 * Récupère le profil complet d'un utilisateur à partir de son identifiant
 * Si l'utilisateur n'est pas dans Supabase, on va le chercher dans l'ancien Firestore
 */
async function getUserProfile(userId) {
  const client = ensureSupabase();
  let row = await supabaseMaybeSingle(
    client.from(TABLES.users).select("*").eq("id", userId),
  );

  if (!row) {
    const legacyProfile = await getLegacyFirestoreUserProfile(userId);
    if (legacyProfile) {
      row = await upsertUserProfile({
        id: userId,
        email: legacyProfile.email || "",
        name: legacyProfile.name || "",
        phone: legacyProfile.phone || "",
        role: legacyProfile.role || "student",
        faculty: legacyProfile.faculty || "",
        level: legacyProfile.level || "",
        field: legacyProfile.field || "",
        createdAt: legacyProfile.createdAt || nowIso(),
        lastActivity: legacyProfile.lastActivity || nowIso(),
      });
    } else {
      try {
        const userRecord = await auth.getUser(userId);
        const claimedRole = normalizeString(userRecord.customClaims?.role);
        row = await upsertUserProfile({
          id: userRecord.uid,
          email: userRecord.email || "",
          name: userRecord.displayName || "",
          phone: userRecord.phoneNumber || "",
          role: claimedRole
            ? normalizeRole(claimedRole)
            : userRecord.customClaims?.admin === true
              ? "admin"
              : "student",
          createdAt: userRecord.metadata.creationTime || nowIso(),
          lastActivity: nowIso(),
          devices: [],
          pushTokens: [],
          subscribed: false,
        });
      } catch (_) {
        return null;
      }
    }
  }

  return syncUserProfileFromLegacyFirestore(userId, row);
}

/**
 * Cherche un utilisateur par son email
 */
async function getUserProfileByEmail(email) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!normalizedEmail) return null;

  const client = ensureSupabase();
  const row = await supabaseMaybeSingle(
    client.from(TABLES.users).select("*").ilike("email", normalizedEmail),
  );

  if (row?.id) {
    return syncUserProfileFromLegacyFirestore(row.id, row);
  }

  try {
    const userRecord = await auth.getUserByEmail(normalizedEmail);
    return getUserProfile(userRecord.uid);
  } catch (_) {
    return null;
  }
}

/**
 * Récupère les données de l'ancien système (Firebase Firestore)
 */
async function getLegacyFirestoreUserProfile(userId) {
  try {
    const snapshot = await admin
      .firestore()
      .collection("users")
      .doc(userId)
      .get();
    if (!snapshot.exists) return null;

    const data = snapshot.data() || {};
    return {
      id: userId,
      email: normalizeString(data.email),
      name: normalizeString(data.name),
      phone: normalizeString(data.phone),
      role: normalizeRole(data.role),
      faculty: normalizeString(data.faculty),
      level: normalizeString(data.level),
      field: normalizeString(data.field),
      createdAt:
        normalizeTimestamp(data.createdAt) ||
        normalizeTimestamp(data.created_at),
      lastActivity:
        normalizeTimestamp(data.lastActivity) ||
        normalizeTimestamp(data.last_activity),
    };
  } catch (_) {
    return null;
  }
}

/**
 * Synchronise les données entre Supabase et l'ancien Firestore pour éviter de perdre des infos
 */
async function syncUserProfileFromLegacyFirestore(userId, currentProfile) {
  const legacyProfile = await getLegacyFirestoreUserProfile(userId);
  if (!legacyProfile || !currentProfile) {
    return currentProfile;
  }

  const updates = {};
  const currentRole = normalizeRole(currentProfile.role);
  const legacyRole = normalizeRole(legacyProfile.role);
  const legacyHasPrivileges = ["admin", "delegate"].includes(legacyRole);

  if (
    legacyHasPrivileges &&
    ["student", "guest"].includes(currentRole) &&
    currentRole !== legacyRole
  ) {
    updates.role = legacyRole;
  }

  for (const key of ["name", "phone", "faculty", "level", "field"]) {
    const currentValue = normalizeString(currentProfile[key]);
    const legacyValue = normalizeString(legacyProfile[key]);
    if (!currentValue && legacyValue) {
      updates[key] = legacyValue;
    }
  }

  if (Object.keys(updates).length === 0) {
    return currentProfile;
  }

  return upsertUserProfile(
    {
      id: userId,
      ...updates,
    },
    currentProfile,
  );
}

/**
 * Récupère un profil ou déclenche une erreur si pas trouvé
 */
async function getUserProfileOrThrow(userId) {
  const row = await getUserProfile(userId);
  if (!row) {
    const error = new Error("User profile not found");
    error.status = 404;
    throw error;
  }
  return row;
}

/**
 * Met à jour ou crée un profil utilisateur dans la base de données
 */
async function upsertUserProfile(payload, base = {}) {
  const client = ensureSupabase();
  const row = toUserRow(payload, base);
  const { data, error } = await client
    .from(TABLES.users)
    .upsert(row, { onConflict: "id" })
    .select("*")
    .single();

  if (error) throw error;
  return data;
}

/**
 * Enregistre une action effectuée par un utilisateur (historique)
 */
async function appendHistory(entry) {
  if (!supabase) return;

  const payload = {
    id: entry.id || uuidv4(),
    user_id: entry.userId || null,
    action: entry.action || "",
    entity_type: entry.entityType || "",
    entity_id: entry.entityId || null,
    metadata: entry.metadata || {},
    created_at: nowIso(),
  };

  try {
    await supabase.from(TABLES.history).insert(payload);
  } catch (_) {
    // History is best-effort and should never block main flows.
  }
}

/**
 * Cherche un fichier via son chemin de stockage
 */
async function findFileDocumentByStoragePath(storagePath) {
  if (!storagePath) return null;
  const client = ensureSupabase();
  return supabaseMaybeSingle(
    client.from(TABLES.files).select("*").eq("storage_path", storagePath),
  );
}

/**
 * Cherche un fichier par son ID unique
 */
async function findFileById(fileId) {
  const client = ensureSupabase();
  return supabaseMaybeSingle(
    client.from(TABLES.files).select("*").eq("id", fileId),
  );
}

/**
 * Liste les fichiers en appliquant des filtres (filière, niveau, etc.)
 */
async function listFiles(filters = {}) {
  const client = ensureSupabase();
  let query = client.from(TABLES.files).select("*").order("uploaded_at", {
    ascending: false,
  });

  for (const key of ["faculty", "level", "field", "unit"]) {
    if (filters[key]) {
      query = query.eq(key, String(filters[key]));
    }
  }

  const { data, error } = await query;
  if (error) throw error;

  const typeFilter = normalizeDocumentType(filters.type);
  if (!typeFilter) return data || [];

  return (data || []).filter(
    (row) => normalizeDocumentType(row.type) === typeFilter,
  );
}

/**
 * Liste les événements à venir
 */
async function listEvents(filters = {}) {
  const client = ensureSupabase();
  const { data, error } = await client
    .from(TABLES.events)
    .select("*")
    .order("date", { ascending: false });

  if (error) throw error;

  return (data || []).filter((row) => {
    if (row.is_global) return true;
    if (filters.faculty && row.faculty !== String(filters.faculty))
      return false;
    if (filters.level && row.level !== String(filters.level)) return false;
    if (filters.field && row.field !== String(filters.field)) return false;
    return true;
  });
}

/**
 * Liste les utilisateurs (pour l'administration)
 */
async function listUsers(filters = {}) {
  const client = ensureSupabase();
  let query = client.from(TABLES.users).select("*").order("created_at", {
    ascending: false,
  });

  if (filters.role) {
    query = query.eq("role", normalizeRole(filters.role));
  }

  const { data, error } = await query;
  if (error) throw error;

  let users = data || [];
  if (filters.query) {
    const needle = String(filters.query).toLowerCase();
    users = users.filter(
      (row) =>
        String(row.email || "")
          .toLowerCase()
          .includes(needle) ||
        String(row.name || "")
          .toLowerCase()
          .includes(needle),
    );
  }

  return users;
}

/**
 * Récupère l'arbre des facultés/niveaux/filières à partir des fichiers existants
 * C'est ce qui permet à l'appli de proposer des menus déroulants intelligents.
 */
async function listFaculties() {
  const client = ensureSupabase();
  const { data, error } = await client
    .from(TABLES.faculties)
    .select("*")
    .order("name", { ascending: true });

  if (error) throw error;

  const faculties = Array.isArray(data) ? [...data] : [];
  const facultyByName = new Map();

  for (const row of faculties) {
    const name = normalizeString(row?.name);
    if (name) {
      facultyByName.set(name, {
        ...row,
        levels: Array.isArray(row.levels) ? [...row.levels] : [],
        fields: normalizeObject(row.fields),
        units: normalizeObject(row.units),
      });
    }
  }

  const { data: fileRows, error: filesError } = await client
    .from(TABLES.files)
    .select("faculty, level, field, unit");

  if (filesError) throw filesError;

  for (const fileRow of fileRows || []) {
    const facultyName = normalizeString(fileRow?.faculty);
    const level = normalizeString(fileRow?.level);
    const field = normalizeString(fileRow?.field);
    const unit = normalizeString(fileRow?.unit);

    if (!facultyName) continue;

    let faculty = facultyByName.get(facultyName);
    if (!faculty) {
      faculty = {
        id: `virtual_${facultyName.toLowerCase().replace(/[^a-z0-9]+/g, "_")}`,
        name: facultyName,
        levels: [],
        fields: {},
        units: {},
        created_at: nowIso(),
        updated_at: nowIso(),
      };
      facultyByName.set(facultyName, faculty);
    }

    if (level && !faculty.levels.includes(level)) {
      faculty.levels.push(level);
    }

    if (level && field) {
      const levelFields = Array.isArray(faculty.fields[level])
        ? [...faculty.fields[level]]
        : [];
      if (!levelFields.includes(field)) {
        levelFields.push(field);
      }
      faculty.fields[level] = levelFields;
    }

    if (level && field && unit) {
      const levelUnits = normalizeObject(faculty.units[level]);
      const fieldUnits = Array.isArray(levelUnits[field])
        ? [...levelUnits[field]]
        : [];
      if (!fieldUnits.includes(unit)) {
        fieldUnits.push(unit);
      }
      levelUnits[field] = fieldUnits;
      faculty.units[level] = levelUnits;
    }
  }

  return Array.from(facultyByName.values()).sort((a, b) =>
    String(a.name || "").localeCompare(String(b.name || "")),
  );
}

/**
 * Crée ou met à jour la structure d'une faculté si elle est mentionnée dans un fichier
 */
async function ensureFacultyPathExists({ faculty, level, field, unit }) {
  const facultyName = normalizeString(faculty);
  const normalizedLevel = normalizeString(level);
  const normalizedField = normalizeString(field);
  const normalizedUnit = normalizeString(unit);

  if (
    !facultyName ||
    !normalizedLevel ||
    !normalizedField ||
    !normalizedUnit
  ) {
    return;
  }

  const client = ensureSupabase();
  const { data, error } = await client
    .from(TABLES.faculties)
    .select("*")
    .eq("name", facultyName)
    .limit(1)
    .maybeSingle();

  if (error && error.code !== "PGRST116") {
    throw error;
  }

  const current = data || {
    id: uuidv4(),
    name: facultyName,
    levels: [],
    fields: {},
    units: {},
    created_at: nowIso(),
  };

  const levels = Array.isArray(current.levels) ? [...current.levels] : [];
  if (!levels.includes(normalizedLevel)) {
    levels.push(normalizedLevel);
  }

  const fields = normalizeObject(current.fields);
  const levelFields = Array.isArray(fields[normalizedLevel])
    ? [...fields[normalizedLevel]]
    : [];
  if (!levelFields.includes(normalizedField)) {
    levelFields.push(normalizedField);
  }
  fields[normalizedLevel] = levelFields;

  const units = normalizeObject(current.units);
  const levelUnits = normalizeObject(units[normalizedLevel]);
  const fieldUnits = Array.isArray(levelUnits[normalizedField])
    ? [...levelUnits[normalizedField]]
    : [];
  if (!fieldUnits.includes(normalizedUnit)) {
    fieldUnits.push(normalizedUnit);
  }
  levelUnits[normalizedField] = fieldUnits;
  units[normalizedLevel] = levelUnits;

  const hasChanged =
    JSON.stringify(levels) !== JSON.stringify(current.levels || []) ||
    JSON.stringify(fields) !== JSON.stringify(normalizeObject(current.fields)) ||
    JSON.stringify(units) !== JSON.stringify(normalizeObject(current.units));

  if (!hasChanged) {
    return;
  }

  const { error: upsertError } = await client.from(TABLES.faculties).upsert(
    {
      id: current.id,
      name: facultyName,
      levels,
      fields,
      units,
      created_at: current.created_at || nowIso(),
      updated_at: nowIso(),
    },
    { onConflict: "id" },
  );

  if (upsertError) throw upsertError;
}

/**
 * Vérifie si une publicité correspond à la filière de l'utilisateur
 */
function adMatchesUser(row, user) {
  if (row?.is_global || row?.isGlobal) {
    return true;
  }

  if (!user) {
    return false;
  }

  return (
    normalizeString(row?.faculty) === normalizeString(user?.faculty) &&
    normalizeString(row?.level) === normalizeString(user?.level) &&
    normalizeString(row?.field) === normalizeString(user?.field)
  );
}

/**
 * Liste les publicités actives depuis Supabase
 */
async function listActiveAdsFromSupabase(req, user = null) {
  const client = ensureSupabase();
  const { data, error } = await client
    .from(TABLES.ads)
    .select("*")
    .eq("is_active", true)
    .order("created_at", { ascending: false });

  if (error) throw error;

  const now = new Date();
  return (data || [])
    .filter((row) => adMatchesUser(row, user))
    .map((row) => adResponse(req, row))
    .filter((ad) => {
      const start = parseDateValue(ad.startDate);
      const end = parseDateValue(ad.endDate);
      return (!start || start <= now) && (!end || end >= now);
    });
}

/**
 * Liste les publicités actives depuis l'ancien système Firestore
 */
async function listActiveAdsFromFirestore(req, user = null) {
  const snapshot = await admin
    .firestore()
    .collection("ads")
    .where("isActive", "==", true)
    .get();

  const now = new Date();
  return snapshot.docs
    .map((doc) => {
      const data = doc.data() || {};
      const firebaseImageUrl = String(data.imageUrl || "");
      const isFirebaseHostedUrl =
        firebaseImageUrl.includes("firebasestorage.googleapis.com") ||
        firebaseImageUrl.startsWith("https://storage.googleapis.com/");
      const isGsUrl = firebaseImageUrl.startsWith("gs://");

      return adResponse(req, {
        id: doc.id,
        title: data.title || "",
        description: data.description || "",
        image_url: firebaseImageUrl,
        storage_path:
          data.storagePath && !isFirebaseHostedUrl && !isGsUrl
            ? data.storagePath
            : null,
        target_url: data.targetUrl || "",
        faculty: data.faculty || "",
        level: data.level || "",
        field: data.field || "",
        is_global: data.isGlobal !== false,
        is_active: data.isActive !== false,
        clicks: Number(data.clicks || 0),
        start_date: normalizeTimestamp(data.startDate),
        end_date: normalizeTimestamp(data.endDate),
        created_at: normalizeTimestamp(data.createdAt),
      });
    })
    .filter((ad) => adMatchesUser(ad, user))
    .filter((ad) => {
      const start = parseDateValue(ad.startDate);
      const end = parseDateValue(ad.endDate);
      return (!start || start <= now) && (!end || end >= now);
    });
}

/**
 * Permet de modifier une faculté en appliquant une fonction de transformation (mutateur)
 */
async function mutateFaculty(facultyId, mutator) {
  const client = ensureSupabase();
  const current = await supabaseMaybeSingle(
    client.from(TABLES.faculties).select("*").eq("id", facultyId),
  );

  if (!current) {
    const error = new Error("Faculty not found");
    error.status = 404;
    throw error;
  }

  const payload = mutator({
    id: current.id,
    name: current.name || "",
    levels: Array.isArray(current.levels) ? [...current.levels] : [],
    fields: normalizeObject(current.fields),
    units: normalizeObject(current.units),
  });

  const { data, error } = await client
    .from(TABLES.faculties)
    .update({
      ...payload,
      updated_at: nowIso(),
    })
    .eq("id", facultyId)
    .select("*")
    .single();

  if (error) throw error;
  return data;
}

/**
 * Vérifie si l'appareil de l'utilisateur est un ordinateur
 */
function deviceIsDesktop(device) {
  return ["Windows", "Linux", "macOS"].includes(String(device?.platform || ""));
}

/**
 * Crée des notifications système pour une liste d'utilisateurs et leur envoie en direct
 */
async function createNotificationsForUsers(targetUserIds, notification) {
  if (!Array.isArray(targetUserIds) || targetUserIds.length === 0) return;

  const client = ensureSupabase();
  const rows = targetUserIds.map((userId) => ({
    id: uuidv4(),
    user_id: userId,
    type: notification.type || "",
    title: notification.title || "",
    body: notification.body || "",
    data: notification,
    read: false,
    timestamp: nowIso(),
  }));

  const { data, error } = await client
    .from(TABLES.notifications)
    .insert(rows)
    .select("*");

  if (error) throw error;

  for (const row of data || []) {
    broadcastNotification(row.user_id, notificationResponse(row));
  }
}

/**
 * Envoie un message à l'application mobile en direct via WebSocket
 */
function broadcastNotification(userId, notification) {
  const connections = clients.get(userId) || [];
  const message = JSON.stringify({
    type: "notification",
    data: notification,
  });

  for (const ws of connections) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(message);
    }
  }
}

/**
 * Prévient les utilisateurs sur ordinateur qu'un nouveau fichier est arrivé
 */
async function notifyDesktopUsersForFile(fileId, fileData) {
  const users = await listUsers({
    role: undefined,
  });

  const targetIds = users
    .filter(
      (user) =>
        user.faculty === (fileData.faculty || "") &&
        user.level === (fileData.level || "") &&
        user.field === (fileData.field || "") &&
        Array.isArray(user.devices) &&
        user.devices.some(deviceIsDesktop),
    )
    .map((user) => user.id);

  await createNotificationsForUsers(targetIds, {
    type: "file",
    id: fileId,
    title: "Nouveau fichier disponible",
    body: `Un nouveau fichier "${fileData.name}" a ete ajoute.`,
  });
}

/**
 * Prévient les utilisateurs sur ordinateur qu'un nouvel événement a été créé
 */
async function notifyDesktopUsersForEvent(eventId, eventData) {
  const users = await listUsers();

  const targetIds = users
    .filter((user) => {
      if (!Array.isArray(user.devices) || !user.devices.some(deviceIsDesktop)) {
        return false;
      }

      if (eventData.is_global) return true;

      return (
        user.faculty === (eventData.faculty || "") &&
        user.level === (eventData.level || "") &&
        user.field === (eventData.field || "")
      );
    })
    .map((user) => user.id);

  await createNotificationsForUsers(targetIds, {
    type: "event",
    id: eventId,
    title: eventData.is_global ? "Nouvel evenement global" : "Nouvel evenement",
    body: eventData.description || eventData.title || "",
    description: eventData.description || "",
    date: normalizeTimestamp(eventData.date) || nowIso(),
    location: eventData.location || "",
    faculty: eventData.faculty || "",
    level: eventData.level || "",
    field: eventData.field || "",
    isGlobal: Boolean(eventData.is_global),
  });
}

/**
 * Prévient les utilisateurs sur ordinateur qu'une nouvelle publicité est parue
 */
async function notifyDesktopUsersForAd(adId, adData) {
  const users = await listUsers();

  const targetIds = users
    .filter((user) => {
      if (!Array.isArray(user.devices) || !user.devices.some(deviceIsDesktop)) {
        return false;
      }

      if (adData.is_global) return true;

      return (
        user.faculty === (adData.faculty || "") &&
        user.level === (adData.level || "") &&
        user.field === (adData.field || "")
      );
    })
    .map((user) => user.id);

  await createNotificationsForUsers(targetIds, {
    type: "ad",
    id: adId,
    title: adData.is_global ? "Nouvelle annonce globale" : "Nouvelle annonce",
    body: adData.description || adData.title || "",
    description: adData.description || "",
    targetUrl: adData.target_url || "",
    imageUrl: adData.image_url || "",
    faculty: adData.faculty || "",
    level: adData.level || "",
    field: adData.field || "",
    isGlobal: Boolean(adData.is_global),
  });
}

/**
 * Envoie une notification "Push" via Google Firebase Cloud Messaging (FCM)
 */
async function sendTopicNotification(message) {
  try {
    await admin.messaging().send(message);
  } catch (error) {
    console.warn("FCM send failed:", error.message);
  }
}

/**
 * Prépare le message pour Google Firebase en incluant le titre, le corps et les données
 */
function buildPushMessage({ topic, data }) {
  const payload = Object.entries(data || {}).reduce((acc, [key, value]) => {
    if (value == null) return acc;
    acc[key] = String(value);
    return acc;
  }, {});

  const title = payload.title || "Nouvelle notification";
  const body = payload.body || "";

  return {
    topic,
    data: payload,
    notification: {
      title,
      body,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "high_importance_channel",
        sound: "default",
      },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: { aps: { sound: "default" } },
    },
  };
}

/**
 * Coordonne l'envoi des notifications quand un fichier est créé
 */
async function notifyForFileCreation(fileId, row) {
  const topic = getTopicForFile({
    faculty: row.faculty,
    level: row.level,
    field: row.field,
  });

  if (topic) {
    await sendTopicNotification(
      buildPushMessage({
        topic,
        data: {
          type: "file",
          id: fileId,
          title: "Nouveau fichier disponible",
          body: `Un nouveau fichier "${row.name}" a ete ajoute dans ${row.type}.`,
        },
      }),
    );
  }

  await notifyDesktopUsersForFile(fileId, row);
}

/**
 * Coordonne l'envoi des notifications quand un événement est créé
 */
async function notifyForEventCreation(eventId, row) {
  const topic = getTopicForEvent({
    isGlobal: Boolean(row.is_global),
    faculty: row.faculty,
    level: row.level,
    field: row.field,
  });

  if (topic) {
    await sendTopicNotification(
      buildPushMessage({
        topic,
        data: {
          type: "event",
          id: eventId,
          title: row.is_global ? "Nouvel evenement global" : "Nouvel evenement",
          body: row.description || row.title || "",
          description: row.description || "",
          date: normalizeTimestamp(row.date) || nowIso(),
          location: row.location || "",
          faculty: row.faculty || "",
          level: row.level || "",
          field: row.field || "",
          isGlobal: row.is_global ? "true" : "false",
        },
      }),
    );
  }

  await notifyDesktopUsersForEvent(eventId, row);
}

/**
 * Coordonne l'envoi des notifications pour une nouvelle publicité
 */
async function notifyForAdCreation(adId, row, req) {
  const topic = getTopicForAd({
    isGlobal: Boolean(row.is_global),
    faculty: row.faculty,
    level: row.level,
    field: row.field,
  });

  if (topic) {
    await sendTopicNotification(
      buildPushMessage({
        topic,
        data: {
          type: "ad",
          id: adId,
          title: row.is_global ? "Nouvelle annonce globale" : "Nouvelle annonce",
          body: row.description || row.title || "",
          description: row.description || "",
          targetUrl: row.target_url || "",
          imageUrl: adResponse(req, row).imageUrl || "",
          faculty: row.faculty || "",
          level: row.level || "",
          field: row.field || "",
          isGlobal: row.is_global ? "true" : "false",
        },
      }),
    );
  }

  await notifyDesktopUsersForAd(adId, row);
}

/**
 * Envoie un fichier binaire vers le stockage Cloudflare R2
 */
async function uploadBufferToR2(storagePath, buffer, contentType) {
  const { client, bucket } = ensureR2();
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: storagePath,
      Body: buffer,
      ContentType: contentType || "application/octet-stream",
    }),
  );
}

/**
 * Supprime un fichier du stockage Cloudflare R2
 */
async function deleteObjectFromR2(storagePath) {
  if (!storagePath) return;
  const { client, bucket } = ensureR2();
  await client.send(
    new DeleteObjectCommand({
      Bucket: bucket,
      Key: storagePath,
    }),
  );
}

/**
 * Récupère un fichier depuis le stockage Cloudflare R2
 */
async function getObjectFromR2(storagePath) {
  const { client, bucket } = ensureR2();
  return client.send(
    new GetObjectCommand({
      Bucket: bucket,
      Key: storagePath,
    }),
  );
}

/**
 * Appelle l'API de Google pour vérifier les identifiants de connexion (email/pass)
 */
async function signInWithPassword(email, password) {
  const response = await axios.post(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${getFirebaseApiKey()}`,
    { email, password, returnSecureToken: true },
  );
  return response.data;
}

/**
 * Rafraîchit la session d'un utilisateur quand son ticket (token) a expiré
 */
async function refreshIdToken(refreshToken) {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });

  const response = await axios.post(
    `https://securetoken.googleapis.com/v1/token?key=${getFirebaseApiKey()}`,
    body.toString(),
    { headers: { "Content-Type": "application/x-www-form-urlencoded" } },
  );
  return response.data;
}

/**
 * Demande à Google d'envoyer un email de réinitialisation de mot de passe
 */
async function sendPasswordReset(email) {
  await axios.post(
    `https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${getFirebaseApiKey()}`,
    { requestType: "PASSWORD_RESET", email },
  );
}

/**
 * S'assure que l'utilisateur qui vient de se connecter possède bien un profil dans notre base de données
 */
async function ensureLoginProfile(loginData) {
  let user = await getUserProfile(loginData.localId);
  if (user) return syncUserProfileFromLegacyFirestore(loginData.localId, user);

  const userRecord = await auth.getUser(loginData.localId);
  user = await upsertUserProfile({
    id: userRecord.uid,
    email: userRecord.email || "",
    name: userRecord.displayName || "",
    phone: userRecord.phoneNumber || "",
    role: "student",
    createdAt: nowIso(),
    lastActivity: nowIso(),
    devices: [],
    pushTokens: [],
    subscribed: false,
  });

  return syncUserProfileFromLegacyFirestore(loginData.localId, user);
}

// ==================== LES GARDIENS (MIDDLEWARES) ====================

/**
 * Gardien de base : Vérifie si l'utilisateur est bien celui qu'il prétend être
 * On regarde le ticket "Bearer Token" envoyé par l'application.
 */
async function verifyToken(req, res, next) {
  try {
    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : null;
    if (!token) return res.status(401).json({ error: "No token provided" });

    // Google vérifie la validité du ticket
    const decoded = await auth.verifyIdToken(token);
    req.userId = decoded.uid;
    req.userEmail = decoded.email || "";
    next(); // C'est bon, on peut passer à la suite
  } catch (_) {
    return res.status(401).json({ error: "Invalid token" });
  }
}

/**
 * Gardien poli : Vérifie l'identité si le ticket est là, mais laisse passer même sans ticket
 */
async function tryVerifyToken(req, res, next) {
  try {
    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : null;
    if (!token) {
      req.userId = null;
      req.userEmail = "";
      return next();
    }
    const decoded = await auth.verifyIdToken(token);
    req.userId = decoded.uid;
    req.userEmail = decoded.email || "";
    next();
  } catch (_) {
    return res.status(401).json({ error: "Invalid token" });
  }
}

/**
 * Gardien d'élite : Seuls les Administrateurs peuvent passer ici
 */
async function requireAdmin(req, res, next) {
  try {
    const user = await getUserProfile(req.userId);
    if (!user || normalizeRole(user.role) !== "admin") {
      return res.status(403).json({ error: "Admin access required" });
    }
    req.currentUserProfile = user;
    next();
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
}

/**
 * Gardien Privilégié : Seuls les Admins ou les Délégués peuvent passer
 */
async function requirePrivileged(req, res, next) {
  try {
    const user = await getUserProfile(req.userId);
    const role = normalizeRole(user?.role);
    if (role !== "admin" && role !== "delegate") {
      return res.status(403).json({ error: "Privileged access required (Admin or Delegate)" });
    }
    req.currentUserProfile = user;
    next();
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
}

// ==================== LOGIQUE DE PAIEMENT ====================

/**
 * Active l'abonnement d'un utilisateur après un paiement réussi
 */
async function applySubscriptionActivation({ transactionId, verification, webhookPayload = null }) {
  const client = ensureSupabase();
  const payment = await supabaseMaybeSingle(client.from(TABLES.payments).select("*").eq("id", transactionId));

  if (!payment) throw new Error(`Payment transaction ${transactionId} not found`);

  const isAccepted = verification?.success === true;
  const paymentDate = new Date();

  const paymentUpdate = {
    verification_message: verification?.message || null,
    payment_date: paymentDate.toISOString(),
    verified_at: nowIso(),
    updated_at: nowIso(),
    webhook_payload: webhookPayload,
    provider_response: verification,
    status: isAccepted ? "accepted" : "failed",
  };

  if (!isAccepted) {
    await client.from(TABLES.payments).update(paymentUpdate).eq("id", transactionId);
    return { activated: false, status: paymentUpdate.status };
  }

  // Si déjà activé, on ne fait rien de plus
  if (["accepted", "fulfilled"].includes(String(payment.status || ""))) {
    await client.from(TABLES.payments).update(paymentUpdate).eq("id", transactionId);
    return { activated: true, status: payment.status };
  }

  const user = await getUserProfileOrThrow(payment.user_id);
  const subscriptionStartDate = paymentDate;
  const subscriptionEndDate = getNextSchoolYearBoundary(paymentDate);
  const subscriptionSchoolYear = getSchoolYearLabel(paymentDate);

  // Mise à jour de l'utilisateur : il devient abonné !
  await client
    .from(TABLES.users)
    .update({
      subscribed: true,
      subscription_start_date: subscriptionStartDate.toISOString(),
      subscription_end_date: subscriptionEndDate.toISOString(),
      subscription_school_year: subscriptionSchoolYear,
      last_subscription_transaction_id: transactionId,
      updated_at: nowIso(),
    })
    .eq("id", user.id);

  // Mise à jour de la transaction
  await client
    .from(TABLES.payments)
    .update({
      ...paymentUpdate,
      status: "fulfilled",
      fulfilled_at: nowIso(),
      subscription_start_date: subscriptionStartDate.toISOString(),
      subscription_end_date: subscriptionEndDate.toISOString(),
      subscription_school_year: subscriptionSchoolYear,
    })
    .eq("id", transactionId);

  return {
    activated: true,
    status: "fulfilled",
    subscriptionStartDate: subscriptionStartDate.toISOString(),
    subscriptionEndDate: subscriptionEndDate.toISOString(),
    subscriptionSchoolYear,
  };
}

/**
 * Initialise un nouveau paiement via PaiementPro
 */
async function createPaiementProCheckout({ user, phone, displayName, baseUrl, source = "app" }) {
  let merchantId;
  try {
    const config = getPaiementProConfig();
    merchantId = config.merchantId;
  } catch (configError) {
    const error = new Error("Payment service misconfiguration");
    error.details = configError.message;
    throw error;
  }

  const client = ensureSupabase();
  const existingSubscription = buildSubscriptionSnapshot(user);
  if (existingSubscription.hasActiveSubscription) {
    const error = new Error("Subscription is already active");
    error.statusCode = 409;
    error.payload = { subscription: existingSubscription };
    throw error;
  }

  const sanitizedPhone = String(phone || user.phone || "").trim();
  if (!sanitizedPhone) {
    const error = new Error("A phone number is required to start the payment");
    error.statusCode = 400;
    throw error;
  }

  const amount = getSubscriptionAmount();
  const transactionId = `UPSUB${Date.now()}${uuidv4().slice(0, 8)}`;
  const schoolYearLabel = getSchoolYearLabel();
  const metadata = { userId: user.id, plan: "annual_school_year", schoolYear: schoolYearLabel, source };
  const safeDisplayName = String(displayName || user.name || "Utilisateur Up2School").trim();
  const [customerFirstName, ...surnameParts] = safeDisplayName.split(" ");
  const customerLastname = surnameParts.join(" ") || "Up2School";

  // On enregistre la transaction en mode "attente"
  await client.from(TABLES.payments).insert({
    id: transactionId,
    provider: "paiement_pro",
    type: "subscription",
    plan_code: "annual_school_year",
    user_id: user.id,
    amount,
    currency: "XOF",
    status: "pending_initialization",
    customer_name: safeDisplayName,
    customer_phone_number: sanitizedPhone,
    metadata,
    school_year_label: schoolYearLabel,
    created_at: nowIso(),
    updated_at: nowIso(),
  });

  const payload = {
    merchantId,
    amount,
    description: "Abonnement Up2School",
    channel: "WAVECI",
    countryCurrencyCode: "952",
    referenceNumber: transactionId,
    customerEmail: user.email || "user@gmail.com",
    customerFirstName: customerFirstName || "Utilisateur",
    customerLastname,
    customerPhoneNumber: sanitizedPhone,
    notificationURL: `${baseUrl}/api/payments/paiement-pro/webhook`,
    returnURL: `${baseUrl}/api/payments/paiement-pro/return?transaction_id=${transactionId}`,
    returnContext: JSON.stringify(metadata),
  };

  // Appel au service de paiement externe
  let paiementProResponse;
  try {
    paiementProResponse = await axios.post(
      "https://paiementpro.net/webservice/onlinepayment/init/curl-init.php",
      payload,
      { headers: { "Content-Type": "application/json", "User-Agent": "Up2School-Backend/2.0" }, timeout: 30000 },
    );
  } catch (axiosError) {
    const errorDetails = { message: axiosError.message, status: axiosError.response?.status, data: axiosError.response?.data };
    await client.from(TABLES.payments).update({ status: "initialization_failed", updated_at: nowIso(), provider_response: errorDetails }).eq("id", transactionId);
    const error = new Error("PaiementPro API call failed");
    error.statusCode = 502;
    error.payload = { details: errorDetails, transactionId };
    throw error;
  }

  const responseData = paiementProResponse.data || {};
  const paymentUrl = responseData?.url;
  if (!paymentUrl) {
    await client.from(TABLES.payments).update({ status: "initialization_failed", updated_at: nowIso(), provider_response: responseData }).eq("id", transactionId);
    const error = new Error("PaiementPro did not return a payment URL");
    error.statusCode = 502;
    error.payload = { details: responseData, transactionId };
    throw error;
  }

  // Tout est OK, on renvoie le lien de paiement à l'application
  await client.from(TABLES.payments).update({ status: "pending_payment", payment_url: paymentUrl, provider_response: responseData, updated_at: nowIso() }).eq("id", transactionId);

  return { transactionId, paymentUrl, amount, currency: "XOF", status: "pending_payment", schoolYearLabel };
}

// ==================== LES ROUTES (LES ADRESSES DE L'API) ====================

/**
 * Route Santé : Permet de vérifier si le serveur est bien vivant
 */
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "up2school-backend",
    timestamp: nowIso(),
    integrations: {
      firebaseProjectId,
      firebaseAdmin: Boolean(firebaseServiceAccount),
      supabase: Boolean(supabase),
      r2: Boolean(r2Client && r2BucketName),
    },
  });
});

/**
 * Inscription : Création d'un nouveau compte
 */
app.post("/api/auth/register", async (req, res) => {
  try {
    const { email, password, name, phone, faculty, level, field } = req.body;
    if (!email || !password || !name) return res.status(400).json({ error: "Missing required fields" });

    // Création chez Google Firebase Auth
    const userRecord = await auth.createUser({ email, password, displayName: name });

    // Création du profil dans notre base de données Supabase
    const user = await upsertUserProfile({
      id: userRecord.uid,
      email,
      name,
      phone: phone || "",
      faculty: faculty || "",
      level: level || "",
      field: field || "",
      role: "student",
      createdAt: nowIso(),
      lastActivity: nowIso(),
      subscribed: false,
    });

    // Connexion immédiate
    const login = await signInWithPassword(email, password);
    await appendHistory({ userId: user.id, action: "auth_register", entityType: "user", entityId: user.id });

    res.json({ success: true, user: userResponse(user), token: login.idToken, refreshToken: login.refreshToken });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

/**
 * Connexion : On vérifie l'email et le mot de passe
 */
app.post("/api/auth/login", async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ error: "Email and password required" });

    const login = await signInWithPassword(email, password);
    let user = await ensureLoginProfile(login);

    const updated = await upsertUserProfile({ id: login.localId, email: login.email || email, lastActivity: nowIso() }, user);
    user = updated;

    await appendHistory({ userId: user.id, action: "auth_login", entityType: "user", entityId: user.id });

    res.json({ success: true, user: userResponse(user), token: login.idToken, refreshToken: login.refreshToken });
  } catch (error) {
    const authError = extractFirebaseAuthError(error, "Connexion impossible");
    res.status(authError.status).json({ error: authError.message });
  }
});

/**
 * Rafraîchir la session : Quand le ticket est expiré, on en demande un nouveau
 */
app.post("/api/auth/refresh", async (req, res) => {
  try {
    const refreshToken = normalizeString(req.body?.refreshToken);
    if (!refreshToken) return res.status(400).json({ error: "Refresh token is required" });

    const refreshed = await refreshIdToken(refreshToken);
    let user = await ensureLoginProfile({ localId: refreshed.user_id, email: refreshed.email || "" });

    user = await upsertUserProfile({ id: refreshed.user_id, email: refreshed.email || user.email || "", lastActivity: nowIso() }, user);

    res.json({ success: true, user: userResponse(user), token: refreshed.id_token, refreshToken: refreshed.refresh_token || refreshToken });
  } catch (error) {
    const authError = extractFirebaseAuthError(error, "Rafraichissement de session impossible");
    res.status(authError.status).json({ error: authError.message });
  }
});

/**
 * Déconnexion : On dit au revoir au serveur
 */
app.post("/api/auth/logout", verifyToken, async (req, res) => {
  res.json({ success: true });
});

/**
 * Vérifier le mot de passe actuel (avant une action sensible)
 */
app.post("/api/auth/verify-password", verifyToken, async (req, res) => {
  try {
    const { password } = req.body;
    if (!password) return res.status(400).json({ error: "Password is required" });

    const user = await auth.getUser(req.userId);
    await signInWithPassword(user.email, password);
    res.json({ success: true });
  } catch (_) {
    res.status(401).json({ error: "Invalid password" });
  }
});

/**
 * Changer le mot de passe
 */
app.post("/api/auth/change-password", verifyToken, async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) return res.status(400).json({ error: "Both passwords are required" });

    const user = await auth.getUser(req.userId);
    await signInWithPassword(user.email, currentPassword);
    await auth.updateUser(req.userId, { password: newPassword });
    res.json({ success: true });
  } catch (error) {
    res.status(400).json({ error: error.message || "Password change failed" });
  }
});

/**
 * Mot de passe oublié : Envoi de l'email de secours
 */
app.post("/api/auth/reset-password", async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required" });
    await sendPasswordReset(email);
    res.json({ success: true });
  } catch (error) {
    res.status(400).json({ error: error.message || "Reset password failed" });
  }
});

/**
 * Supprimer mon propre compte
 */
app.delete("/api/auth/account", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    await client.from(TABLES.users).delete().eq("id", req.userId);
    await client.from(TABLES.notifications).delete().eq("user_id", req.userId);
    await client.from(TABLES.history).delete().eq("user_id", req.userId);
    await auth.deleteUser(req.userId);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Liste des utilisateurs (Admin seulement)
 */
app.get("/api/users", verifyToken, requireAdmin, async (req, res) => {
  try {
    const users = await listUsers({ role: req.query.role, query: req.query.query });
    res.json(users.map(userResponse));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Voir le profil d'un utilisateur spécifique (Moi-même ou Admin)
 */
app.get("/api/users/:userId", verifyToken, async (req, res) => {
  try {
    if (req.userId !== req.params.userId) {
      const currentUser = await getUserProfile(req.userId);
      if (!currentUser || normalizeRole(currentUser.role) !== "admin") return res.status(403).json({ error: "Unauthorized" });
    }

    const user = await getUserProfile(req.params.userId);
    if (!user) return res.status(404).json({ error: "User not found" });
    res.json(userResponse(user));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Modifier un profil utilisateur (Moi-même ou Admin)
 */
app.put("/api/users/:userId", verifyToken, async (req, res) => {
  try {
    const isSelf = req.userId === req.params.userId;
    const currentUser = await getUserProfile(req.userId);
    const isAdmin = normalizeRole(currentUser?.role) === "admin";
    if (!isSelf && !isAdmin) return res.status(403).json({ error: "Unauthorized" });

    const existing = await getUserProfile(req.params.userId);
    const updated = await upsertUserProfile({ ...req.body, id: req.params.userId }, existing || { id: req.params.userId, email: req.body.email || "" });
    res.json(userResponse(updated));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put(
  "/api/users/:userId/role",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      const client = ensureSupabase();
      await client
        .from(TABLES.users)
        .update({
          role: normalizeRole(req.body.role),
          updated_at: nowIso(),
        })
        .eq("id", req.params.userId);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.post("/api/users/:userId/last-activity", verifyToken, async (req, res) => {
  try {
    if (req.userId !== req.params.userId) {
      return res.status(403).json({ error: "Unauthorized" });
    }

    const client = ensureSupabase();
    await client
      .from(TABLES.users)
      .update({
        last_activity: nowIso(),
        updated_at: nowIso(),
      })
      .eq("id", req.params.userId);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.delete("/api/users/:userId", verifyToken, async (req, res) => {
  try {
    const currentUser = await getUserProfile(req.userId);
    const isAdmin = normalizeRole(currentUser?.role) === "admin";
    const isSelf = req.userId === req.params.userId;
    if (!isAdmin && !isSelf) {
      return res.status(403).json({ error: "Unauthorized" });
    }

    const client = ensureSupabase();
    await client.from(TABLES.users).delete().eq("id", req.params.userId);
    await client
      .from(TABLES.notifications)
      .delete()
      .eq("user_id", req.params.userId);
    await client.from(TABLES.history).delete().eq("user_id", req.params.userId);

    if (isAdmin && !isSelf) {
      await auth.deleteUser(req.params.userId).catch(() => {});
    }

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/subscriptions/me", verifyToken, async (req, res) => {
  try {
    const currentUser = await getUserProfile(req.userId);
    if (!currentUser) {
      return res.status(404).json({ error: "User profile not found" });
    }

    const subscription = buildSubscriptionSnapshot(currentUser);
    res.json({
      ...subscription,
      schoolYearStart: getCurrentSchoolYearStart().toISOString(),
      schoolYearLabel: getSchoolYearLabel(),
      price: getSubscriptionAmount(),
      currency: "XOF",
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/subscriptions/checkout", verifyToken, async (req, res) => {
  try {
    const currentUser = await getUserProfile(req.userId);
    if (!currentUser) {
      return res.status(404).json({ error: "User profile not found" });
    }

    const checkout = await createPaiementProCheckout({
      user: currentUser,
      phone: req.body.phone,
      displayName: req.body.name,
      baseUrl: resolveBaseUrl(req),
      source: "app",
    });

    res.json(checkout);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    res.status(statusCode).json({
      error: error.message,
      ...(error.details ? { details: error.details } : {}),
      ...(error.payload || {}),
      ...(statusCode === 500
        ? {
            hint: "Please set PAIEMENT_PRO_MERCHANT_ID environment variable (e.g., PP-F324)",
          }
        : {}),
    });
  }
});

app.post("/api/subscriptions/web-checkout", async (req, res) => {
  try {
    const email = String(req.body.email || "").trim().toLowerCase();
    const phone = String(req.body.phone || "").trim();

    if (!email) {
      return res.status(400).json({ error: "Email is required" });
    }

    if (!phone) {
      return res.status(400).json({ error: "Phone number is required" });
    }

    const currentUser = await getUserProfileByEmail(email);
    if (!currentUser) {
      return res.status(404).json({
        error: "No Up2School account found for this email address",
      });
    }

    const checkout = await createPaiementProCheckout({
      user: currentUser,
      phone,
      displayName: currentUser.name,
      baseUrl: resolveBaseUrl(req),
      source: "web_apple",
    });

    res.json({
      ...checkout,
      email: currentUser.email,
      name: currentUser.name || "",
    });
  } catch (error) {
    const statusCode = error.statusCode || 500;
    res.status(statusCode).json({
      error: error.message,
      ...(error.details ? { details: error.details } : {}),
      ...(error.payload || {}),
      ...(statusCode === 500
        ? {
            hint: "Please set PAIEMENT_PRO_MERCHANT_ID environment variable (e.g., PP-F324)",
          }
        : {}),
    });
  }
});

app.get("/subscribe-apple", (req, res) => {
  const baseUrl = resolveBaseUrl(req);
  const webCheckoutUrl = `${baseUrl}/api/subscriptions/web-checkout`;

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(200).send(`<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Up2School - Accès iOS & macOS</title>
    <style>
      :root {
        color-scheme: light;
        --bg-1: #eef2f9;
        --bg-2: #cfddee;
        --card: #ffffff;
        --primary: #1f6e50;
        --primary-deep: #194f3a;
        --secondary: #2c3e66;
        --text: #1e293b;
        --muted: #5b6b7f;
        --border: #dce5f0;
        --warning: #fff7e6;
        --warning-border: #f2c46d;
        --danger: #a33232;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: linear-gradient(145deg, var(--bg-1) 0%, var(--bg-2) 100%);
        color: var(--text);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px;
      }
      .card {
        width: min(100%, 560px);
        background: var(--card);
        border-radius: 28px;
        padding: 28px;
        box-shadow: 0 24px 60px rgba(15, 23, 42, 0.15);
      }
      h1 {
        margin: 0 0 10px;
        font-size: clamp(2rem, 4vw, 2.5rem);
        color: var(--primary);
      }
      p { line-height: 1.55; }
      .muted { color: var(--muted); }
      .notice {
        background: var(--warning);
        border: 1px solid var(--warning-border);
        border-radius: 18px;
        padding: 14px 16px;
        margin: 18px 0 22px;
      }
      .steps { display: grid; gap: 16px; }
      .step {
        border: 1px solid var(--border);
        border-radius: 20px;
        padding: 18px;
      }
      .step.hidden { display: none; }
      .step-title {
        font-size: 1.05rem;
        font-weight: 700;
        margin-bottom: 12px;
        color: var(--primary-deep);
      }
      label {
        display: block;
        font-size: 0.95rem;
        margin-bottom: 8px;
        font-weight: 600;
      }
      input {
        width: 100%;
        border: 1px solid var(--border);
        border-radius: 14px;
        padding: 14px 16px;
        font-size: 1rem;
        outline: none;
      }
      input:focus {
        border-color: var(--primary);
        box-shadow: 0 0 0 3px rgba(31, 110, 80, 0.12);
      }
      .actions {
        display: flex;
        gap: 12px;
        margin-top: 14px;
        flex-wrap: wrap;
      }
      button {
        border: 0;
        border-radius: 999px;
        padding: 13px 20px;
        font-size: 1rem;
        font-weight: 700;
        cursor: pointer;
      }
      .btn-primary {
        background: var(--secondary);
        color: #fff;
      }
      .btn-secondary {
        background: #eef3f8;
        color: var(--primary);
      }
      .status {
        min-height: 24px;
        margin-top: 12px;
        font-size: 0.95rem;
      }
      .status.error { color: var(--danger); }
      .status.success { color: var(--primary-deep); }
      .account-pill {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        background: #eef5f0;
        color: var(--primary-deep);
        border-radius: 999px;
        padding: 8px 14px;
        font-weight: 600;
      }
      @media (max-width: 640px) {
        .card {
          padding: 22px 18px;
          border-radius: 22px;
        }
        .actions { flex-direction: column; }
        button { width: 100%; }
      }
    </style>
  </head>
  <body>
    <main class="card">
      <h1>Accès iOS & macOS</h1>
      <p class="muted">
        Renseignez l'email associé à votre compte Up2School, puis votre numéro
        de téléphone pour continuer.
      </p>
      <div class="notice">
        Ce parcours web est réservé aux comptes existants Up2School. Le statut
        de votre accès restera ensuite disponible dans l'application.
      </div>

      <div class="steps">
        <section id="emailStep" class="step">
          <div class="step-title">1. Vérifier votre email</div>
          <label for="email">Email</label>
          <input id="email" type="email" autocomplete="email" placeholder="vous@exemple.com" />
          <div class="actions">
            <button id="emailButton" class="btn-primary" type="button">Continuer</button>
          </div>
          <div id="emailStatus" class="status"></div>
        </section>

        <section id="phoneStep" class="step hidden">
          <div class="step-title">2. Renseigner votre numéro</div>
          <div id="accountPill" class="account-pill"></div>
          <div style="height: 14px;"></div>
          <label for="phone">Numéro Mobile Money / Orange Money</label>
          <input id="phone" type="tel" inputmode="tel" autocomplete="tel" placeholder="670000000" />
          <div class="actions">
            <button id="checkoutButton" class="btn-primary" type="button">Continuer vers le paiement</button>
            <button id="backButton" class="btn-secondary" type="button">Modifier l'email</button>
          </div>
          <div id="phoneStatus" class="status"></div>
        </section>
      </div>
    </main>

    <script>
      const webCheckoutUrl = ${JSON.stringify(webCheckoutUrl)};
      let selectedEmail = "";

      const emailStep = document.getElementById("emailStep");
      const phoneStep = document.getElementById("phoneStep");
      const emailInput = document.getElementById("email");
      const phoneInput = document.getElementById("phone");
      const emailStatus = document.getElementById("emailStatus");
      const phoneStatus = document.getElementById("phoneStatus");
      const accountPill = document.getElementById("accountPill");
      const emailButton = document.getElementById("emailButton");
      const checkoutButton = document.getElementById("checkoutButton");
      const backButton = document.getElementById("backButton");

      function setStatus(element, message, type = "") {
        element.textContent = message || "";
        element.className = "status" + (type ? " " + type : "");
      }

      function showPhoneStep(email) {
        selectedEmail = email;
        accountPill.textContent = email;
        emailStep.classList.add("hidden");
        phoneStep.classList.remove("hidden");
        setStatus(emailStatus, "");
        setStatus(phoneStatus, "");
        window.setTimeout(() => phoneInput.focus(), 50);
      }

      emailButton.addEventListener("click", () => {
        const email = emailInput.value.trim().toLowerCase();
        if (!email) {
          setStatus(emailStatus, "Veuillez entrer votre email.", "error");
          emailInput.focus();
          return;
        }
        showPhoneStep(email);
      });

      backButton.addEventListener("click", () => {
        phoneStep.classList.add("hidden");
        emailStep.classList.remove("hidden");
        setStatus(phoneStatus, "");
        window.setTimeout(() => emailInput.focus(), 50);
      });

      checkoutButton.addEventListener("click", async () => {
        const phone = phoneInput.value.trim();
        if (!selectedEmail) {
          phoneStep.classList.add("hidden");
          emailStep.classList.remove("hidden");
          return;
        }
        if (!phone) {
          setStatus(phoneStatus, "Veuillez entrer votre numéro de téléphone.", "error");
          phoneInput.focus();
          return;
        }

        checkoutButton.disabled = true;
        setStatus(phoneStatus, "Préparation du paiement...", "success");

        try {
          const response = await fetch(webCheckoutUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ email: selectedEmail, phone }),
          });

          const data = await response.json().catch(() => ({}));
          if (!response.ok) {
            throw new Error(data.error || "Le paiement n'a pas pu être préparé.");
          }

          if (!data.paymentUrl) {
            throw new Error("Lien de paiement indisponible.");
          }

          setStatus(phoneStatus, "Redirection vers le paiement...", "success");
          window.location.href = data.paymentUrl;
        } catch (error) {
          setStatus(phoneStatus, error.message || "Une erreur est survenue.", "error");
          checkoutButton.disabled = false;
        }
      });
    </script>
  </body>
</html>`);
});

app.get(
  "/api/subscriptions/transactions/:transactionId/status",
  verifyToken,
  async (req, res) => {
    try {
      const client = ensureSupabase();
      const payment = await supabaseMaybeSingle(
        client
          .from(TABLES.payments)
          .select("*")
          .eq("id", req.params.transactionId),
      );

      if (!payment) {
        return res.status(404).json({ error: "Transaction not found" });
      }

      const currentUser = await getUserProfile(req.userId);
      const isAdmin = normalizeRole(currentUser?.role) === "admin";
      if (payment.user_id !== req.userId && !isAdmin) {
        return res.status(403).json({ error: "Unauthorized" });
      }

      let latestPayment = payment;
      if (
        [
          "pending_payment",
          "waiting_for_customer",
          "pending_initialization",
        ].includes(String(payment.status || ""))
      ) {
        // For PaiementPro, verification happens through the application
        // The payment status is updated when the user returns from payment URL
        await applySubscriptionActivation({
          transactionId: req.params.transactionId,
          verification: { success: true },
        });

        latestPayment = await supabaseMaybeSingle(
          client
            .from(TABLES.payments)
            .select("*")
            .eq("id", req.params.transactionId),
        );
      }

      const user = await getUserProfile(payment.user_id);
      res.json({
        ...paymentResponse(latestPayment),
        subscription: buildSubscriptionSnapshot(user),
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.get("/api/payments/cinetpay/webhook", (req, res) => {
  res.status(200).send("OK");
});

app.post("/api/payments/cinetpay/webhook", async (req, res) => {
  // Deprecated: CinetPay webhooks are no longer supported
  // PaiementPro webhooks can be sent here if needed
  res.status(200).send("OK");
});

app.get("/api/payments/paiement-pro/webhook", (req, res) => {
  res.status(200).send("OK");
});

app.post("/api/payments/paiement-pro/webhook", async (req, res) => {
  // PaiementPro webhook handler
  // Payment verification happens when user returns to app
  res.status(200).send("OK");
});

async function handlePaiementProReturn(req, res) {
  const transactionId = String(
    req.query.transaction_id || req.body.transaction_id || "",
  ).trim();
  let statusMessage = "Votre paiement est en cours de confirmation.";

  if (transactionId && supabase) {
    try {
      const payment = await supabaseMaybeSingle(
        supabase.from(TABLES.payments).select("*").eq("id", transactionId),
      );

      if (payment) {
        if (["accepted", "fulfilled"].includes(String(payment.status || ""))) {
          statusMessage =
            "Paiement confirmé. Revenez dans l'application Up2School.";
        } else if (String(payment.status || "").includes("failed")) {
          statusMessage =
            "Paiement non abouti. Revenez dans l'application pour réessayer.";
        }
      }
    } catch (_) {}

    // Mark payment as accepted when user returns successfully
    if (transactionId) {
      try {
        await applySubscriptionActivation({
          transactionId,
          verification: { success: true },
        });
      } catch (error) {
        console.error("Error updating payment status:", error);
      }
    }
  }

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(200).send(`<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Up2School - Paiement</title>
    <style>
      body { font-family: Arial, sans-serif; background: #f6f8f7; color: #17352a; margin: 0; padding: 24px; }
      .card { max-width: 520px; margin: 10vh auto; background: #ffffff; border-radius: 16px; padding: 24px; box-shadow: 0 16px 40px rgba(0,0,0,0.08); }
      h1 { margin-top: 0; font-size: 24px; }
      p { line-height: 1.5; }
      .muted { color: #5a6b63; font-size: 14px; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Abonnement Up2School</h1>
      <p>${statusMessage}</p>
      <p class="muted">Transaction: ${transactionId || "indisponible"}</p>
      <p class="muted">L'activation définitive est faite côté serveur après vérification du paiement.</p>
    </div>
  </body>
</html>`);
}

app.get("/api/payments/cinetpay/return", handlePaiementProReturn);
app.post("/api/payments/cinetpay/return", handlePaiementProReturn);

app.get("/api/payments/paiement-pro/return", handlePaiementProReturn);
app.post("/api/payments/paiement-pro/return", handlePaiementProReturn);

app.get("/api/faculties", async (req, res) => {
  try {
    const faculties = await listFaculties();
    res.json(faculties.map(facultyResponse));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.delete(
  "/api/faculties/:facultyId",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      const client = ensureSupabase();
      await client
        .from(TABLES.faculties)
        .delete()
        .eq("id", req.params.facultyId);
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.post(
  "/api/faculties/:facultyId/levels",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      await mutateFaculty(req.params.facultyId, (faculty) => {
        const levels = new Set(faculty.levels);
        levels.add(String(req.body.level || "").trim());
        return { levels: Array.from(levels) };
      });
      res.json({ success: true });
    } catch (error) {
      res.status(error.status || 400).json({ error: error.message });
    }
  },
);

app.delete(
  "/api/faculties/:facultyId/levels",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      await mutateFaculty(req.params.facultyId, (faculty) => ({
        levels: faculty.levels.filter((level) => level !== req.body.level),
      }));
      res.json({ success: true });
    } catch (error) {
      res.status(error.status || 400).json({ error: error.message });
    }
  },
);

app.post(
  "/api/faculties/:facultyId/fields",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      await mutateFaculty(req.params.facultyId, (faculty) => {
        const fields = { ...faculty.fields };
        const levelFields = Array.isArray(fields[req.body.level])
          ? [...fields[req.body.level]]
          : [];
        if (!levelFields.includes(req.body.field)) {
          levelFields.push(req.body.field);
        }
        fields[req.body.level] = levelFields;
        return { fields };
      });
      res.json({ success: true });
    } catch (error) {
      res.status(error.status || 400).json({ error: error.message });
    }
  },
);

app.delete(
  "/api/faculties/:facultyId/fields",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      await mutateFaculty(req.params.facultyId, (faculty) => {
        const fields = { ...faculty.fields };
        fields[req.body.level] = (fields[req.body.level] || []).filter(
          (field) => field !== req.body.field,
        );
        return { fields };
      });
      res.json({ success: true });
    } catch (error) {
      res.status(error.status || 400).json({ error: error.message });
    }
  },
);

app.post(
  "/api/faculties/:facultyId/units",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      await mutateFaculty(req.params.facultyId, (faculty) => {
        const units = { ...faculty.units };
        const levelUnits = { ...(units[req.body.level] || {}) };
        const fieldUnits = Array.isArray(levelUnits[req.body.field])
          ? [...levelUnits[req.body.field]]
          : [];
        if (!fieldUnits.includes(req.body.unit)) {
          fieldUnits.push(req.body.unit);
        }
        levelUnits[req.body.field] = fieldUnits;
        units[req.body.level] = levelUnits;
        return { units };
      });
      res.json({ success: true });
    } catch (error) {
      res.status(error.status || 400).json({ error: error.message });
    }
  },
);

app.delete(
  "/api/faculties/:facultyId/units",
  verifyToken,
  requireAdmin,
  async (req, res) => {
    try {
      await mutateFaculty(req.params.facultyId, (faculty) => {
        const units = { ...faculty.units };
        const levelUnits = { ...(units[req.body.level] || {}) };
        levelUnits[req.body.field] = (levelUnits[req.body.field] || []).filter(
          (unit) => unit !== req.body.unit,
        );
        units[req.body.level] = levelUnits;
        return { units };
      });
      res.json({ success: true });
    } catch (error) {
      res.status(error.status || 400).json({ error: error.message });
    }
  },
);

app.get("/api/files", tryVerifyToken, async (req, res) => {
  try {
    const currentUser = req.userId ? await getUserProfile(req.userId) : null;

    const files = await listFiles(req.query);
    const enriched = files.map((row) =>
      fileResponse(req, row, {
        user:
          currentUser != null
            ? {
                id: req.userId,
                ...currentUser,
              }
            : null,
      }),
    );

    const page = Number(req.query.page || 0);
    const pageSize = Number(req.query.pageSize || enriched.length || 20);
    const start = page * pageSize;
    const end = start + pageSize;

    res.json(enriched.slice(start, end));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/files/:fileId", tryVerifyToken, async (req, res) => {
  try {
    const currentUser = req.userId ? await getUserProfile(req.userId) : null;

    const row = await findFileById(req.params.fileId);
    if (!row) {
      return res.status(404).json({ error: "File not found" });
    }

    res.json(
      fileResponse(req, row, {
        user:
          currentUser != null
            ? {
                id: req.userId,
                ...currentUser,
              }
            : null,
      }),
    );
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/files", verifyToken, requirePrivileged, async (req, res) => {
  try {
    const currentUser = await getUserProfile(req.userId);
    if (!currentUser) {
      return res.status(404).json({ error: "User profile not found" });
    }

    const client = ensureSupabase();
    const payload = toFileRow(req.body, req.userId);
    const { data, error } = await client
      .from(TABLES.files)
      .upsert(payload, { onConflict: "id" })
      .select("*")
      .single();

    if (error) throw error;

    await ensureFacultyPathExists({
      faculty: payload.faculty,
      level: payload.level,
      field: payload.field,
      unit: payload.unit,
    });

    await notifyForFileCreation(payload.id, data);
    await appendHistory({
      userId: req.userId,
      action: "file_create",
      entityType: "file",
      entityId: payload.id,
      metadata: {
        faculty: payload.faculty,
        level: payload.level,
        field: payload.field,
      },
    });

    res.json(
      fileResponse(req, data, {
        user: {
          id: req.userId,
          ...currentUser,
        },
      }),
    );
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.delete("/api/files/:fileId", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const currentUser = await getUserProfile(req.userId);
    const row = await findFileById(req.params.fileId);
    if (!row) {
      return res.status(404).json({ error: "File not found" });
    }

    if (!canDeleteFile(row, currentUser, req.userId)) {
      return res.status(403).json({ error: "Unauthorized" });
    }

    const storagePath = row.storage_path || extractStoragePathFromUrl(row.url);
    await deleteObjectFromR2(storagePath).catch(() => {});
    await client.from(TABLES.files).delete().eq("id", req.params.fileId);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put(
  "/api/files/:fileId/reading-progress",
  verifyToken,
  async (req, res) => {
    try {
      const client = ensureSupabase();
      const currentUser = await getUserProfile(req.userId);
      const row = await findFileById(req.params.fileId);
      if (!row) {
        return res.status(404).json({ error: "File not found" });
      }

      const access = buildFileAccess(currentUser, row);
      if (!access.canAccess) {
        return res.status(403).json({ error: "Subscription required" });
      }

      const readingProgress = {
        ...normalizeObject(row.reading_progress),
        [req.body.userId]: Number(req.body.progress || 0),
      };

      await client
        .from(TABLES.files)
        .update({
          reading_progress: readingProgress,
          last_opened: nowIso(),
          updated_at: nowIso(),
        })
        .eq("id", req.params.fileId);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.post("/api/files/:fileId/views", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const currentUser = await getUserProfile(req.userId);
    const row = await findFileById(req.params.fileId);
    if (!row) {
      return res.status(404).json({ error: "File not found" });
    }

    const access = buildFileAccess(currentUser, row);
    if (!access.canAccess) {
      return res.status(403).json({ error: "Subscription required" });
    }

    const viewedBy = Array.isArray(row.viewed_by) ? [...row.viewed_by] : [];
    const userId = String(req.body.userId || req.userId);
    const alreadyViewed = viewedBy.includes(userId);
    if (!alreadyViewed) {
      viewedBy.push(userId);
    }

    await client
      .from(TABLES.files)
      .update({
        viewed_by: viewedBy,
        view_count: alreadyViewed
          ? Number(row.view_count || 0)
          : Number(row.view_count || 0) + 1,
        last_opened: nowIso(),
        updated_at: nowIso(),
      })
      .eq("id", req.params.fileId);

    await appendHistory({
      userId,
      action: "file_view",
      entityType: "file",
      entityId: req.params.fileId,
    });

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/files/:fileId/favorite", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const row = await findFileById(req.params.fileId);
    if (!row) {
      return res.status(404).json({ error: "File not found" });
    }

    const userId = String(req.body.userId || req.userId);
    const favorites = Array.isArray(row.favorites) ? [...row.favorites] : [];
    const index = favorites.indexOf(userId);
    if (index >= 0) {
      favorites.splice(index, 1);
    } else {
      favorites.push(userId);
    }

    await client
      .from(TABLES.files)
      .update({
        favorites,
        updated_at: nowIso(),
      })
      .eq("id", req.params.fileId);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post(
  "/api/storage/upload",
  verifyToken,
  requirePrivileged,
  upload.single("file"),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "File is required" });
      }

      const requestedPath = req.body.path || `files/${req.userId}`;
      const safeOriginalName = req.file.originalname.replace(/\s+/g, "_");
      const storagePath = `${requestedPath}/${Date.now()}_${safeOriginalName}`;
      await uploadBufferToR2(storagePath, req.file.buffer, req.file.mimetype);

      res.json({
        success: true,
        storagePath,
        downloadUrl: buildStorageProxyUrl(
          req,
          storagePath,
          req.file.originalname,
        ),
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.delete("/api/storage/object", verifyToken, requirePrivileged, async (req, res) => {
  try {
    const storagePath =
      req.body.storagePath || extractStoragePathFromUrl(req.body.url);
    if (!storagePath) {
      return res.status(400).json({ error: "Storage path is required" });
    }

    await deleteObjectFromR2(storagePath).catch(() => {});
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get(
  "/api/storage/download-url/:fileId",
  tryVerifyToken,
  async (req, res) => {
    try {
      const currentUser = req.userId ? await getUserProfile(req.userId) : null;

      const row = await findFileById(req.params.fileId);
      if (!row) {
        return res.status(404).json({ error: "File not found" });
      }

      const data = fileResponse(req, row, {
        user:
          currentUser != null
            ? {
                id: req.userId,
                ...currentUser,
              }
            : null,
      });

      if (!data.canAccess) {
        return res.status(403).json({ error: "Subscription required" });
      }

      res.json({
        downloadUrl: data.url,
        fileName: data.fileName,
        mimeType: data.fileType,
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.get("/api/storage/object/*", async (req, res) => {
  try {
    const storagePath = decodeURIComponent(req.params[0] || "");
    const relatedFile = await findFileDocumentByStoragePath(storagePath);

    if (relatedFile) {
      const accessToken = String(req.query.access_token || "");
      const tokenPayload = accessToken
        ? verifyStorageAccessToken(accessToken, storagePath)
        : null;
      const guestAccess = buildFileAccess(null, relatedFile).canAccess;

      if (!tokenPayload && !guestAccess) {
        return res.status(403).send("Subscription required");
      }
    }

    const object = await getObjectFromR2(storagePath);
    const fileName = req.query.name || storagePath.split("/").pop();

    if (object.ContentType) {
      res.setHeader("Content-Type", object.ContentType);
    }
    if (object.ContentLength != null) {
      res.setHeader("Content-Length", String(object.ContentLength));
    }
    res.setHeader("Content-Disposition", `inline; filename="${fileName}"`);

    object.Body.pipe(res);
  } catch (_) {
    res.status(404).send("Not found");
  }
});

app.get("/api/events", verifyToken, async (req, res) => {
  try {
    const events = await listEvents(req.query);
    res.json(events.map(eventResponse));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/events/:eventId", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const row = await supabaseMaybeSingle(
      client.from(TABLES.events).select("*").eq("id", req.params.eventId),
    );

    if (!row) {
      return res.status(404).json({ error: "Event not found" });
    }

    res.json(eventResponse(row));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/events", verifyToken, requirePrivileged, async (req, res) => {
  try {
    const client = ensureSupabase();
    const payload = toEventRow(req.body, req.userId);
    const { data, error } = await client
      .from(TABLES.events)
      .upsert(payload, { onConflict: "id" })
      .select("*")
      .single();

    if (error) throw error;

    await notifyForEventCreation(payload.id, data);
    await appendHistory({
      userId: req.userId,
      action: "event_create",
      entityType: "event",
      entityId: payload.id,
    });

    res.json(eventResponse(data));
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.delete("/api/events/:eventId", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const currentUser = await getUserProfile(req.userId);
    const row = await supabaseMaybeSingle(
      client.from(TABLES.events).select("*").eq("id", req.params.eventId),
    );

    if (!row) {
      return res.status(404).json({ error: "Event not found" });
    }

    const role = normalizeRole(currentUser?.role);
    const isAdmin = role === "admin";
    const isOwner =
      row.created_by === req.userId ||
      row.created_by === currentUser?.id ||
      row.created_by === currentUser?.email;
    const isDelegateInSameScope =
      role === "delegate" &&
      !row.is_global &&
      academicScopeMatches(row, currentUser);
    if (!isAdmin && !isOwner && !isDelegateInSameScope) {
      return res.status(403).json({ error: "Unauthorized" });
    }

    for (const imageUrl of Array.isArray(row.image_urls)
      ? row.image_urls
      : []) {
      const storagePath = extractStoragePathFromUrl(imageUrl);
      await deleteObjectFromR2(storagePath).catch(() => {});
    }

    await client.from(TABLES.events).delete().eq("id", req.params.eventId);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post(
  "/api/notifications/register-device",
  verifyToken,
  async (req, res) => {
    try {
      const { deviceId, platform } = req.body;
      if (!deviceId || !platform) {
        return res
          .status(400)
          .json({ error: "deviceId and platform required" });
      }

      const client = ensureSupabase();
      const user = await getUserProfileOrThrow(req.userId);
      const devices = Array.isArray(user.devices) ? [...user.devices] : [];
      const filtered = devices.filter((device) => device.deviceId !== deviceId);
      filtered.push({
        deviceId,
        platform,
        registeredAt: nowIso(),
      });

      await client
        .from(TABLES.users)
        .update({
          devices: filtered,
          updated_at: nowIso(),
        })
        .eq("id", req.userId);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.post(
  "/api/notifications/register-push-token",
  verifyToken,
  async (req, res) => {
    try {
      const { token, platform } = req.body;
      if (!token) {
        return res.status(400).json({ error: "token is required" });
      }

      const client = ensureSupabase();
      const user = await getUserProfileOrThrow(req.userId);
      const pushTokens = Array.isArray(user.push_tokens)
        ? [...user.push_tokens]
        : [];
      const filtered = pushTokens.filter((entry) => entry.token !== token);
      filtered.push({
        token,
        platform,
        createdAt: nowIso(),
      });

      await client
        .from(TABLES.users)
        .update({
          push_tokens: filtered,
          updated_at: nowIso(),
        })
        .eq("id", req.userId);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.post(
  "/api/notifications/unregister-push-token",
  verifyToken,
  async (req, res) => {
    try {
      const { token } = req.body;
      const client = ensureSupabase();
      const user = await getUserProfileOrThrow(req.userId);
      const pushTokens = Array.isArray(user.push_tokens)
        ? [...user.push_tokens]
        : [];

      await client
        .from(TABLES.users)
        .update({
          push_tokens: pushTokens.filter((entry) => entry.token !== token),
          updated_at: nowIso(),
        })
        .eq("id", req.userId);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.get("/api/notifications/poll", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const { data, error } = await client
      .from(TABLES.notifications)
      .select("*")
      .eq("user_id", req.userId)
      .eq("read", false)
      .order("timestamp", { ascending: false });

    if (error) throw error;
    res.json((data || []).map(notificationResponse));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post(
  "/api/notifications/mark-read/:notificationId",
  verifyToken,
  async (req, res) => {
    try {
      const client = ensureSupabase();
      await client
        .from(TABLES.notifications)
        .update({
          read: true,
          read_at: nowIso(),
        })
        .eq("id", req.params.notificationId)
        .eq("user_id", req.userId);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  },
);

app.get("/api/ads/active", tryVerifyToken, async (req, res) => {
  try {
    const currentUser = req.userId ? await getUserProfile(req.userId) : null;

    try {
      const supabaseAds = await listActiveAdsFromSupabase(req, currentUser);
      if (supabaseAds.length > 0) {
        return res.json(supabaseAds);
      }
    } catch (error) {
      console.warn("Supabase active ads lookup failed:", error.message);
    }

    const firebaseAds = await listActiveAdsFromFirestore(req, currentUser);
    res.json(firebaseAds);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get("/api/ads", verifyToken, requireAdmin, async (req, res) => {
  try {
    const client = ensureSupabase();
    const { data, error } = await client
      .from(TABLES.ads)
      .select("*")
      .order("created_at", { ascending: false });

    if (error) throw error;
    res.json((data || []).map((row) => adResponse(req, row)));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post("/api/ads/upload-image", verifyToken, requireAdmin, upload.single("file"), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: "No file uploaded" });

    const storagePath = `ads/${Date.now()}-${uuidv4().slice(0, 8)}${path.extname(req.file.originalname).toLowerCase()}`;
    await uploadBufferToR2(storagePath, req.file.buffer, req.file.mimetype);

    const imageUrl = buildStorageProxyUrl(req, storagePath, "ad.jpg");
    res.json({ success: true, imageUrl, storagePath });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
// ==================== ROUTES DES PUBLICITÉS (ADS) ====================

/**
 * Liste des publicités (Admin voit tout, Utilisateur voit les siennes)
 */
app.get("/api/ads", tryVerifyToken, async (req, res) => {
  try {
    const user = req.userId ? await getUserProfile(req.userId) : null;
    const isAdmin = normalizeRole(user?.role) === "admin";

    if (isAdmin) {
      const client = ensureSupabase();
      const { data, error } = await client.from(TABLES.ads).select("*").order("created_at", { ascending: false });
      if (error) throw error;
      return res.json((data || []).map((row) => adResponse(req, row)));
    }

    const ads = await listActiveAdsFromSupabase(req, user);
    res.json(ads);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Créer une publicité (Admin seulement)
 */
app.post("/api/ads", verifyToken, requireAdmin, async (req, res) => {
  try {
    const validationError = validateAdPayload(req.body);
    if (validationError) return res.status(400).json({ error: validationError });

    const client = ensureSupabase();
    const row = toAdRow(req.body, req.userId);
    const { data, error } = await client.from(TABLES.ads).insert(row).select("*").single();

    if (error) throw error;
    if (data.is_active) await notifyForAdCreation(data.id, data, req);

    res.json(adResponse(req, data));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Supprimer une publicité (Admin seulement)
 */
app.delete("/api/ads/:adId", verifyToken, requireAdmin, async (req, res) => {
  try {
    const client = ensureSupabase();
    const { data: ad } = await client.from(TABLES.ads).select("storage_path").eq("id", req.params.adId).single();
    await client.from(TABLES.ads).delete().eq("id", req.params.adId);
    if (ad?.storage_path) await deleteObjectFromR2(ad.storage_path);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Compter un clic sur une publicité
 */
app.post("/api/ads/:adId/click", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const { data: ad } = await client.from(TABLES.ads).select("clicks").eq("id", req.params.adId).single();
    if (!ad) return res.status(404).json({ error: "Ad not found" });

    await client.from(TABLES.ads).update({ clicks: (ad.clicks || 0) + 1 }).eq("id", req.params.adId);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Uploader une image pour une publicité (Admin seulement)
 */
app.post("/api/ads/upload-image", verifyToken, requireAdmin, upload.single("file"), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: "No file uploaded" });

    const storagePath = `ads/${Date.now()}-${uuidv4().slice(0, 8)}${path.extname(req.file.originalname).toLowerCase()}`;
    await uploadBufferToR2(storagePath, req.file.buffer, req.file.mimetype);

    const imageUrl = buildStorageProxyUrl(req, storagePath, "ad.jpg");
    res.json({ success: true, imageUrl, storagePath });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==================== ROUTES DES NOTIFICATIONS ====================

/**
 * Enregistrer un appareil pour recevoir des notifications directes (WebSocket)
 */
app.post("/api/notifications/register-device", verifyToken, async (req, res) => {
  try {
    const { device } = req.body;
    if (!device) return res.status(400).json({ error: "Device info is required" });

    const user = await getUserProfileOrThrow(req.userId);
    const devices = Array.isArray(user.devices) ? [...user.devices] : [];
    const existingIndex = devices.findIndex((d) => d.id === device.id);

    if (existingIndex >= 0) devices[existingIndex] = { ...devices[existingIndex], ...device, lastSeen: nowIso() };
    else devices.push({ ...device, lastSeen: nowIso() });

    await upsertUserProfile({ id: req.userId, devices });
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Enregistrer un jeton FCM (pour les notifications Push sur mobile)
 */
app.post("/api/notifications/register-push-token", verifyToken, async (req, res) => {
  try {
    const { token, deviceId } = req.body;
    if (!token) return res.status(400).json({ error: "Token is required" });

    const user = await getUserProfileOrThrow(req.userId);
    const tokens = Array.isArray(user.push_tokens) ? [...user.push_tokens] : [];
    if (!tokens.some((t) => (typeof t === "string" ? t === token : t.token === token))) {
      tokens.push({ token, deviceId, createdAt: nowIso() });
    }

    await upsertUserProfile({ id: req.userId, pushTokens: tokens });
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Supprimer un jeton Push
 */
app.post("/api/notifications/unregister-push-token", verifyToken, async (req, res) => {
  try {
    const { token } = req.body;
    const user = await getUserProfileOrThrow(req.userId);
    const tokens = (Array.isArray(user.push_tokens) ? user.push_tokens : []).filter((t) => (typeof t === "string" ? t !== token : t.token !== token));
    await upsertUserProfile({ id: req.userId, pushTokens: tokens });
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Récupérer mes notifications non lues (Mode manuel)
 */
app.get("/api/notifications/poll", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    const { data, error } = await client.from(TABLES.notifications).select("*").eq("user_id", req.userId).eq("read", false).order("timestamp", { ascending: false }).limit(50);
    if (error) throw error;
    res.json((data || []).map(notificationResponse));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Marquer une notification comme lue
 */
app.post("/api/notifications/mark-read/:notificationId", verifyToken, async (req, res) => {
  try {
    const client = ensureSupabase();
    await client.from(TABLES.notifications).update({ read: true, read_at: nowIso() }).eq("id", req.params.notificationId).eq("user_id", req.userId);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==================== GESTION DES WEBSOCKETS (CONEXIONS EN DIRECT) ====================

wss.on("connection", (ws, req) => {
  let userId = null;

  ws.on("message", async (message) => {
    try {
      const payload = JSON.parse(message.toString());
      if (payload.type === "auth" && payload.token) {
        // L'utilisateur s'identifie en direct
        const decoded = await auth.verifyIdToken(payload.token);
        userId = decoded.uid;
        const userConnections = clients.get(userId) || [];
        userConnections.push(ws);
        clients.set(userId, userConnections);
        ws.send(JSON.stringify({ type: "auth_success" }));
      }
    } catch (_) {}
  });

  ws.on("close", () => {
    if (userId) {
      const userConnections = clients.get(userId) || [];
      const updated = userConnections.filter((c) => c !== ws);
      if (updated.length === 0) clients.delete(userId);
      else clients.set(userId, updated);
    }
  });
});

// ==================== DÉMARRAGE DU SERVEUR ====================

const PORT = process.env.PORT || 8080;
server.listen(PORT, "0.0.0.0", () => {
  console.log(`
  🚀 Serveur Up2School prêt !
  📡 Adresse : http://0.0.0.0:${PORT}
  🛠️  Firebase : ${firebaseProjectId}
  📦 Supabase : ${supabaseUrl ? "Connecté" : "Non configuré"}
  ☁️  R2 Bucket : ${r2BucketName || "Non configuré"}
  `);
});

module.exports = app;
