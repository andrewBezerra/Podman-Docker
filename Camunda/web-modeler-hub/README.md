# Camunda Web Modeler (Hub) — Self-Managed 8.10

Stack standalone do **Web Modeler** do Camunda 8.10. No 8.10 o Web Modeler é o componente
**Hub** (`camunda/hub`), com o Management **Identity** + **Keycloak** + **PostgreSQL** + **Mailpit**
como dependências. Derivado do `docker-compose-hub.yaml` oficial da distribuição 8.10
(github.com/camunda/camunda-distributions).

Difere do `../docker-compose-web-modeler.yaml` deste repositório, que é da linha anterior
(componentes `web-modeler-*` + keycloak bitnami). Este é o 8.10 com Hub.

## Serviços e portas

| Serviço | Imagem | Porta (host) |
| --- | --- | --- |
| hub (Web Modeler) | `camunda/hub:8.10.4` | 8070 |
| hub-websockets | `camunda/hub-websockets:8.10.4` | 8060 |
| hub-db | `postgres:15-alpine3.22` | — |
| identity | `camunda/identity:8.10.2` | 8084 |
| keycloak | `camunda/keycloak:quay-26.6.4` | 18080 (`/auth`) |
| postgres (keycloak+identity) | `postgres:15-alpine3.22` | — |
| mailpit | `axllent/mailpit:v1.21.8` | 8075 (UI), 1025 (SMTP) |

As versões ficam no `.env` (`CAMUNDA_HUB_VERSION`, `CAMUNDA_IDENTITY_VERSION`, etc.).

## Como subir

```sh
cp .env.example .env   # valores demo da distribuição; troque os segredos para uso sério
docker compose up -d   # ou: docker-compose up -d (v2 pelo socket do podman)
```

A ordem de dependência já está no compose: postgres → keycloak → identity (cria o realm
`camunda-platform` e os clients, incl. `web-modeler`) → hub.

- **Web Modeler:** http://localhost:8070 — login `demo` / `demo`.
- **Keycloak (admin):** http://localhost:18080/auth — `admin` / `admin`.
- **Mailpit (e-mails do Modeler):** http://localhost:8075

## Consistência do issuer

O login OIDC exige que navegador e contêineres concordem na URL do Keycloak. No `.env`:
`HOST` é a URL que o navegador usa (o issuer do token) e `KEYCLOAK_HOST` é como os contêineres
alcançam o Keycloak. Por padrão `HOST=localhost` e `KEYCLOAK_HOST=host.docker.internal`. Para
expor na LAN, aponte os dois para o IP/host da máquina e ajuste os *redirect URIs* do client
`web-modeler` no realm.

## Onde roda

Implantado no servidor de teste 192.168.0.115 como `~/camunda-sm` (sobre Podman, docker-compose
v2 pelo socket). Substitui o Camunda basic (`~/camunda`, aposentado) como alvo OIDC.
