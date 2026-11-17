# Architecture locale

Navigateur -> nginx (port 8087 hôte, 80 conteneur)
  - sert le frontend (build Vite)
  - /api et /health -> backend (Express, 3007)
backend -> PostgreSQL (db:5432, volume pgdata)
backend -> Resend (API externe, optionnelle)

## Choix
- Frontend : build multi-étapes (node puis nginx)
- Backend : node:20-alpine, utilisateur non-root
- Persistance : volume nommé pgdata ; init.sql exécuté au premier démarrage
- Secrets : variables dans .env (non versionné)
