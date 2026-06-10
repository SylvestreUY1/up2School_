# Architecture Up2School

## Cible

- Firebase Authentication: identite utilisateur
- Firebase Cloud Messaging: notifications push
- Supabase: base de donnees principale
- Cloudflare R2: stockage des documents et images
- Render: API backend, websocket desktop et paiement

## Repartition

- `functions/server.js`
  API Express pour mobile et desktop
- `supabase/schema.sql`
  schema SQL de reference pour les tables metier
- `render.yaml`
  configuration de deploiement Render
- `functions/.env.example`
  variables d'environnement attendues

## Tables Supabase

- `user_profiles`
  profils enrichis, role, abonnement, appareils, tokens push
- `files`
  metadonnees des documents et controle d'acces
- `events`
  annonces / evenements
- `faculties`
  filtres academiques
- `ads`
  annonces publicitaires
- `notifications`
  notifications desktop et historique court
- `payment_transactions`
  suivi du paiement CinetPay
- `activity_history`
  historique d'activite

## Notes importantes

- Les secrets Firebase, Supabase, R2 et CinetPay ne doivent pas etre commits.
- Render doit pointer sur `functions/` avec `npm start`.
- Les uploads passent par l'API puis sont stockes dans R2.
- Les profils ne doivent plus etre lus directement depuis Firestore cote application.
