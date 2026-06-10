/**
 * FICHIER : index.js
 * RÔLE : Fonctions "Cloud" (dans le nuage) de Firebase.
 * Ce code s'exécute automatiquement sur les serveurs de Google quand quelque chose se passe
 * dans la base de données Firestore ou selon un emploi du temps (Cron Jobs).
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

// Initialisation de l'outil Admin de Firebase pour avoir tous les droits
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// ==================== LES PETITS OUTILS (UTILITAIRES) ====================

/**
 * Transforme un texte en un format "propre" pour les adresses (Base64)
 * Utile pour créer des "Topics" (canaux de discussion) sans caractères interdits.
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
 * Transforme n'importe quel format de date en texte standard (ISO)
 */
function toIsoDateString(value) {
  if (!value) return "";

  if (typeof value?.toDate === "function") {
    return value.toDate().toISOString();
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? value : parsed.toISOString();
  }

  return "";
}

/**
 * Calcule le nom du "canal" (topic) pour un événement
 * (Ex: events_global ou faculte_SES_niveau_L1...)
 */
function getTopicForEvent(eventData) {
  const { isGlobal, faculty, level, field } = eventData;
  if (isGlobal) {
    return "events_global";
  }
  const sanitizedFaculty = encodeTopicSegment(faculty);
  const sanitizedLevel = encodeTopicSegment(level);
  const sanitizedField = encodeTopicSegment(field);

  if (!sanitizedFaculty || !sanitizedLevel || !sanitizedField) {
    return "";
  }

  return `faculte_${sanitizedFaculty}_niveau_${sanitizedLevel}_filiere_${sanitizedField}`;
}

/**
 * Calcule le nom du "canal" (topic) pour un fichier
 */
function getTopicForFile(fileData) {
  const { faculty, level, field } = fileData;
  const sanitizedFaculty = encodeTopicSegment(faculty);
  const sanitizedLevel = encodeTopicSegment(level);
  const sanitizedField = encodeTopicSegment(field);

  if (!sanitizedFaculty || !sanitizedLevel || !sanitizedField) {
    return "";
  }

  return `faculte_${sanitizedFaculty}_niveau_${sanitizedLevel}_filiere_${sanitizedField}`;
}

// ==================== LES ACTIONS AUTOMATIQUES ====================

/**
 * ACTION 1 : Alerter quand un nouveau FICHIER est ajouté
 * Dès qu'un document est créé dans le dossier "files" de la base de données.
 */
exports.sendFileNotification = onDocumentCreated(
  "files/{fileId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const file = snap.data();
    const { type, name } = file;
    const fileId = event.params.fileId;

    // On cherche à qui envoyer cette alerte (quel canal ?)
    const topic = getTopicForFile(file);
    if (!topic) {
      console.log("Topic invalide pour fichier, abandon");
      return;
    }

    // Le message qu'on va envoyer sur le téléphone
    const message = {
      data: {
        type: "file",
        id: fileId,
        title: "Nouveau fichier disponible",
        body: `Un nouveau fichier "${name}" a été ajouté dans ${type}.`,
      },
      android: { priority: "high" },
      topic: topic,
    };

    try {
      // Google envoie le message à tous ceux qui écoutent ce canal
      await admin.messaging().send(message);
      console.log(`Notification fichier envoyée au topic ${topic}`);
    } catch (err) {
      console.error("Erreur envoi notification fichier :", err);
    }
  },
);

/**
 * ACTION 2 : Alerter quand un nouvel ÉVÉNEMENT est créé
 */
exports.sendEventNotification = onDocumentCreated(
  "events/{eventId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const eventData = snap.data();

    // Si on a déjà envoyé l'alerte, on ne recommence pas
    if (eventData.notificationSent === true) return;

    const { title, description } = eventData;
    const eventId = event.params.eventId;

    const topic = getTopicForEvent(eventData);
    if (!topic) {
      console.log("Topic invalide pour événement, abandon");
      return;
    }

    const bodyText = description
      ? `Événement : ${title} - ${description}`
      : `Événement : ${title}`;

    const message = {
      data: {
        type: "event",
        id: eventId,
        title: eventData.isGlobal
          ? "Nouvel événement global"
          : "Nouvel événement",
        body: bodyText,
        description: description || "",
        date: toIsoDateString(eventData.date),
        location: eventData.location || "",
        faculty: eventData.faculty || "",
        level: eventData.level || "",
        field: eventData.field || "",
        isGlobal: eventData.isGlobal ? "true" : "false",
      },
      android: { priority: "high" },
      topic: topic,
    };

    try {
      await admin.messaging().send(message);
      console.log(`Notification événement envoyée au topic ${topic}`);
      // On note dans la base de données que c'est fait
      await db.collection("events").doc(eventId).update({
        notificationSent: true,
      });
    } catch (err) {
      console.error("Erreur envoi notification événement :", err);
    }
  },
);

/**
 * ACTION 3 : Le ménage quotidien (Suppression vieux événements)
 * Se lance toutes les 24 heures.
 */
exports.autoDeleteOldEvents = onSchedule(
  { schedule: "every 24 hours", timeZone: "UTC" },
  async () => {
    // On calcule la date d'il y a 24 heures
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

    // On cherche les vieux événements
    const oldEvents = await db
      .collection("events")
      .where("date", "<", cutoffTimestamp)
      .get();

    if (oldEvents.empty) {
      console.log("Aucun événement à supprimer");
      return;
    }

    // On les supprime tous d'un coup (batch)
    const batch = db.batch();
    oldEvents.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    console.log(`${oldEvents.size} événements supprimés`);
  },
);

/**
 * ACTION 4 : Supprimer les gens qui ne viennent plus (Inactifs)
 * Se lance tous les 45 jours.
 */
exports.deleteInactiveUsers = onSchedule(
  { schedule: "every 45 days", timeZone: "UTC" },
  async () => {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 45);
    const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

    // On cherche les utilisateurs qui n'ont rien fait depuis 45 jours
    const usersSnapshot = await db
      .collection("users")
      .where("lastActivity", "<", cutoffTimestamp)
      .get();

    let deletedCount = 0;

    for (const doc of usersSnapshot.docs) {
      const userId = doc.id;

      try {
        // On les supprime de l'authentification ET de la base de données
        await admin.auth().deleteUser(userId);
        await doc.ref.delete();
        deletedCount++;
      } catch (err) {
        console.error(`Erreur suppression ${userId}:`, err);
      }
    }

    console.log(`Utilisateurs supprimés : ${deletedCount}`);
  },
);

/**
 * ACTION 5 : Nettoyer les pubs périmées
 * Se lance chaque semaine.
 */
exports.cleanExpiredAdsWeekly = onSchedule(
  { schedule: "every 7 days", timeZone: "UTC" },
  async () => {
    const now = new Date();

    const snapshot = await db
      .collection("ads")
      .where("endDate", "<=", now)
      .get();

    if (snapshot.empty) {
      console.log("Aucune annonce expirée");
      return;
    }

    const batch = db.batch();
    snapshot.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    console.log(`${snapshot.size} annonces supprimées`);
  },
);
