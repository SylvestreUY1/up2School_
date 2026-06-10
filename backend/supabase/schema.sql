/**
 * FICHIER : schema.sql
 * RÔLE : Définit la structure de la base de données (Supabase / PostgreSQL).
 * C'est ici qu'on définit les "tiroirs" (tables) où seront rangées les informations.
 */

-- Outil pour générer des identifiants sécurisés
create extension if not exists "pgcrypto";

-- 1. TABLE DES UTILISATEURS (Les profils)
create table if not exists user_profiles (
  id text primary key,             -- Identifiant unique (celui de Firebase)
  email text not null unique,      -- Adresse email (unique pour chaque personne)
  name text default '',            -- Nom complet
  phone text default '',           -- Numéro de téléphone
  role text not null default 'student', -- Rôle (étudiant, délégué, admin...)
  faculty text default '',         -- Faculté (ex: SES, Science...)
  level text default '',           -- Niveau (ex: L1, L2, Master...)
  field text default '',           -- Filière (ex: Informatique, Gestion...)
  created_at timestamptz not null default now(), -- Date de création du compte
  updated_at timestamptz not null default now(), -- Dernière modification
  last_activity timestamptz,       -- Dernière fois que la personne est venue
  devices jsonb not null default '[]'::jsonb,      -- Liste des appareils connectés
  push_tokens jsonb not null default '[]'::jsonb,  -- Jetons pour les notifications push
  subscribed boolean not null default false,       -- Est-ce qu'il a un abonnement payé ?
  subscription_start_date timestamptz,             -- Début de l'abonnement
  subscription_end_date timestamptz,               -- Fin de l'abonnement
  subscription_school_year text,                   -- Année scolaire (ex: 2023-2024)
  last_subscription_transaction_id text            -- ID du dernier paiement
);

-- 2. TABLE DES FACULTÉS (L'organisation de l'université)
create table if not exists faculties (
  id text primary key,
  name text not null,              -- Nom de la faculté
  levels jsonb not null default '[]'::jsonb, -- Liste des niveaux (L1, L2...)
  fields jsonb not null default '{}'::jsonb, -- Liste des filières
  units jsonb not null default '{}'::jsonb,  -- Liste des matières (UE)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3. TABLE DES FICHIERS (Les documents partagés)
create table if not exists files (
  id text primary key,
  name text not null,              -- Nom affiché
  url text default '',             -- Lien vers le fichier
  file_name text not null,         -- Nom réel du fichier sur le serveur
  file_type text not null,         -- Type (PDF, Image...)
  faculty text default '',
  level text default '',
  field text default '',
  unit text default '',            -- Matière concernée
  type text default '',            -- Catégorie (Cours, TD, Exam...)
  size bigint,                     -- Taille en octets
  uploaded_at timestamptz not null default now(),
  publish_date timestamptz not null default now(),
  uploaded_by text not null references user_profiles(id) on delete cascade, -- Qui l'a posté ?
  favorites jsonb not null default '[]'::jsonb,    -- Qui l'a mis en favori ?
  viewed_by jsonb not null default '[]'::jsonb,    -- Qui l'a lu ?
  download_count integer not null default 0,
  view_count integer not null default 0,
  reading_progress jsonb not null default '{}'::jsonb, -- Progression de lecture
  last_opened timestamptz,
  storage_path text,               -- Emplacement sur le stockage Cloud (R2)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Index pour accélérer les recherches de fichiers
create index if not exists idx_files_filters
  on files (faculty, level, field, unit, type);

-- 4. TABLE DES ÉVÉNEMENTS (Le calendrier)
create table if not exists events (
  id text primary key,
  title text not null,             -- Titre de l'événement
  description text default '',
  date timestamptz not null,       -- Date et heure
  location text default '',        -- Lieu
  faculty text default '',
  level text default '',
  field text default '',
  created_by text not null references user_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  image_urls jsonb not null default '[]'::jsonb,
  is_global boolean not null default false, -- Est-ce que tout le monde doit le voir ?
  reminder_48h_sent boolean not null default false, -- Rappel 48h envoyé ?
  reminder_12h_sent boolean not null default false, -- Rappel 12h envoyé ?
  notification_sent boolean not null default false  -- Notification immédiate envoyée ?
);

create index if not exists idx_events_filters
  on events (is_global, faculty, level, field, date desc);

-- 5. TABLE DES PUBLICITÉS (Ads)
create table if not exists ads (
  id text primary key,
  title text not null,
  description text default '',
  image_url text default '',
  storage_path text,
  target_url text default '',      -- Lien vers lequel la pub envoie
  faculty text default '',
  level text default '',
  field text default '',
  is_global boolean not null default true,
  is_active boolean not null default true,  -- Pub affichée ou non
  clicks integer not null default 0,        -- Nombre de clics total
  start_date timestamptz not null default now(),
  end_date timestamptz,
  created_by text references user_profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_ads_filters
  on ads (is_global, faculty, level, field, start_date desc);

-- 6. TABLE DES NOTIFICATIONS (Les alertes reçues par l'utilisateur)
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references user_profiles(id) on delete cascade,
  type text not null,              -- Type (file, event, ad...)
  title text not null,
  body text default '',
  data jsonb not null default '{}'::jsonb,
  read boolean not null default false,      -- Est-ce que l'utilisateur l'a lue ?
  timestamp timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists idx_notifications_unread
  on notifications (user_id, read, timestamp desc);

-- 7. TABLE DES TRANSACTIONS DE PAIEMENT
create table if not exists payment_transactions (
  id text primary key,
  provider text not null,          -- CinetPay, PaiementPro, etc.
  type text not null,              -- Type d'achat
  plan_code text,
  user_id text not null references user_profiles(id) on delete cascade,
  amount integer not null,         -- Montant (en CFA)
  currency text not null,
  status text not null,            -- pending, success, failed...
  customer_name text,
  customer_phone_number text,
  metadata jsonb,
  school_year_label text,
  payment_date timestamptz,
  verified_at timestamptz,
  fulfilled_at timestamptz,        -- Moment où l'abonnement a été activé
  payment_url text,                -- Lien vers la page de paiement
  provider_response jsonb,         -- Réponse technique du service de paiement
  webhook_payload jsonb,           -- Données envoyées par le service à notre serveur
  subscription_start_date timestamptz,
  subscription_end_date timestamptz,
  subscription_school_year text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 8. TABLE DE L'HISTORIQUE (Qui fait quoi ?)
create table if not exists activity_history (
  id uuid primary key default gen_random_uuid(),
  user_id text references user_profiles(id) on delete cascade,
  action text not null,            -- L'action (ex: upload_file, login...)
  entity_type text not null,       -- Le type d'objet concerné
  entity_id text,                  -- L'ID de l'objet
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_history_user_date
  on activity_history (user_id, created_at desc);
