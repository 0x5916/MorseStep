# API Documentation

*Generated: September 21, 2026*
*Base URL: http://localhost:8080*
*API Version: v1*

---

## Table of Contents
1. [Endpoints Overview](#endpoints-overview)
2. [Health Check](#health-check)
3. [Authentication](#authentication)
4. [User Management](#user-management)
5. [Settings Management](#settings-management)
6. [Progress Tracking](#progress-tracking)
7. [Forum](#forum)
8. [Error Handling](#error-handling)

---

## Endpoints Overview

| Method | Path                            | Description                                | Auth Required |
|--------|--------------------------------|-------------------------------------------|---------------|
| GET    | /v1/health                     | Health check endpoint                     | No            |
| POST   | /v1/auth/register              | Register new user account                 | No            |
| POST   | /v1/auth/login                 | Login with credentials                    | No            |
| POST   | /v1/auth/logout                | Logout and revoke refresh token           | No            |
| POST   | /v1/auth/refresh               | Refresh access token                      | No            |
| POST   | /v1/auth/send-verification-email | Send verification email                   | Yes           |
| POST   | /v1/auth/verify-email          | Verify email with OTP code                | Yes           |
| GET    | /v1/user/me                    | Get current user info                     | Yes           |
| PUT    | /v1/user/callsign              | Update user callsign                      | Yes           |
| PUT    | /v1/user/email                 | Update user email                         | Yes           |
| PUT    | /v1/user/password              | Update user password                      | Yes           |
| GET    | /v1/settings/all               | Get all settings (CW + Page)              | Yes           |
| GET    | /v1/settings/cw                | Get CW settings                           | Yes           |
| GET    | /v1/settings/page              | Get Page settings                         | Yes           |
| POST   | /v1/settings/cw                | Update CW settings                        | Yes           |
| POST   | /v1/settings/page              | Update Page settings                      | Yes           |
| GET    | /v1/cw/progress                | Get all progress records                  | Yes           |
| PUT    | /v1/cw/progress                | Add/Create new progress record            | Yes           |
| GET    | /v1/forum/threads              | List forum threads (cursor paginated)     | No            |
| GET    | /v1/forum/threads/:id          | Get a forum thread                        | No            |
| GET    | /v1/forum/threads/:id/replies  | Get nested reply tree of a thread         | No            |
| POST   | /v1/forum/threads              | Create a forum thread                     | Verified email |
| POST   | /v1/forum/threads/:id/replies  | Create a reply (optionally nested)        | Verified email |
| DELETE | /v1/forum/threads/:id          | Delete own thread                         | Author        |
| DELETE | /v1/forum/replies/:id          | Delete own reply                          | Author        |
| GET    | /v1/hello                      | Test authenticated endpoint               | Yes           |

---

## Health Check

### GET /v1/health
**Health check endpoint - no authentication required**

**Response (200)**:
```json
{
  "status": "healthy",
  "timestamp": 1711270200
}
```

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/health
```

---

## Authentication

### POST /v1/auth/register
**Register a new user account**

**Authentication**: None

**Request Body**:
```json
{
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Error Responses**:
| Status | Error Code              | Message                     |
|--------|------------------------|------------------------------|
| 400    | `INVALID_REQUEST_BODY` | Invalid request body         |
| 401    | `INVALID_CREDENTIALS`  | Invalid credentials          |
| 500    | `TOKEN_ISSUE_FAILED`   | Failed to issue token        |
| 500    | `INTERNAL_SERVER_ERROR`| Internal error               |

**Example cURL**:
```bash
curl -X POST http://localhost:8080/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "johndoe",
    "password": "securepassword123"
  }'
```

---

### POST /v1/auth/logout
**Logout and revoke the refresh token**

**Authentication**: Required (any valid token)

**Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response (200)**:
```json
{

### POST /v1/auth/send-verification-email
**Send email verification code to user's email**

**Authentication**: Bearer JWT (access token)

**Request Body**: Empty (uses authenticated user's email)

**Rate Limiting**: One request per minute (Retry-After header included)

**Response (200)**:
```json
{
  "message": "Verification email sent"
}
```

**Error Responses**:
| Status | Error Code                      | Message                                          |
|--------|--------------------------------|--------------------------------------------------|
| 400    | `EMAIL_ALREADY_VERIFIED`       | Email is already verified                        |
| 401    | `AUTH_HEADER_REQUIRED`         | Missing or invalid token                         |
| 409    | `EMAIL_VERIFIED_BY_ANOTHER_ACCOUNT` | Email verified by another account         |
| 429    | `VERIFICATION_RATE_LIMITED`    | Please wait before requesting another email     |
| 500    | `DATABASE_FAILURE`             | Database failure                                 |
| 500    | `VERIFICATION_SEND_FAILED`     | Failed to send verification email                |

**Example cURL**:
```bash
curl -X POST http://localhost:8080/v1/auth/send-verification-email \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json"
```

---

### POST /v1/auth/verify-email
**Verify email using OTP code sent via email**

**Authentication**: Bearer JWT (access token)

**Request Body**:
```json
{
  "code": "123456"
}
```

**Validation Rules**:
- `code`: Exactly 6 numeric characters

**Response (200)**:
```json
{
  "message": "Email verified"
}
```

**Error Responses**:
| Status | Error Code                      | Message                                          |
|--------|--------------------------------|--------------------------------------------------|
| 400    | `INVALID_REQUEST_BODY`         | Invalid request body                             |
| 400    | `EMAIL_ALREADY_VERIFIED`       | Email is already verified                        |
| 400    | `VERIFICATION_CODE_INVALID`    | Invalid verification code                        |
| 400    | `VERIFICATION_CODE_EXPIRED`    | Verification code expired                        |
| 401    | `AUTH_HEADER_REQUIRED`         | Missing or invalid token                         |
| 409    | `EMAIL_VERIFIED_BY_ANOTHER_ACCOUNT` | Email verified by another account         |
| 500    | `DATABASE_FAILURE`             | Database failure                                 |

**Example cURL**:
```bash
curl -X POST http://localhost:8080/v1/auth/verify-email \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "123456"
  }'
```

---

## User Management

### GET /v1/user/me
**Get current authenticated user information**

**Authentication**: Bearer JWT (access token)

**Response (200)**:
```json
{
  "call_sign": "N0CALL",
  "username": "johndoe",
  "email": "john@example.com",
  "email_verified": true,
  "created_at": "2026-03-20T10:30:00Z"
}
```

**Notes**: `call_sign` can be null if not set

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/user/me \
  -H "Authorization: Bearer <access_token>"
```

---

### PUT /v1/user/callsign
**Update user's call sign**

**Authentication**: Bearer JWT (access token)

**Request Body**:
```json
{
  "call_sign": "N0CALL"
}
```

**Response (200)**:
```json
{
  "message": "Call sign updated"
}
```

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 400    | `INVALID_REQUEST_BODY` | Invalid request body         |
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 409    | `CALL_SIGN_ALREADY_IN_USE` | Call sign already in use |
| 500    | `INTERNAL_SERVER_ERROR`| Failed to update call sign  |

**Example cURL**:
```bash
curl -X PUT http://localhost:8080/v1/user/callsign \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "call_sign": "N0CALL"
  }'
```

---

### PUT /v1/user/email
**Update user's email address**

**Authentication**: Bearer JWT (access token)

**Request Body**:
```json
{
  "email": "newemail@example.com"
}
```

**Validation Rules**:
- `email`: Valid email format, max 254 characters, must be different from current email

**Response (200)**:
```json
{
  "message": "Email updated"
}
```

**Notes**: Email verification status resets to false after update

**Error Responses**:
| Status | Error Code                      | Message                                          |
|--------|--------------------------------|--------------------------------------------------|
| 400    | `INVALID_REQUEST_BODY`         | Invalid request body                             |
| 400    | `EMAIL_UNCHANGED`              | New email must be different from current email  |
| 401    | `AUTH_HEADER_REQUIRED`         | Missing or invalid token                         |
| 409    | `EMAIL_VERIFIED_BY_ANOTHER_ACCOUNT` | Email verified by another account         |
| 409    | `EMAIL_ALREADY_IN_USE`         | Email already in use                             |
| 500    | `DATABASE_FAILURE`             | Database failure                                 |
| 500    | `INTERNAL_SERVER_ERROR`        | Failed to update email                           |

**Example cURL**:
```bash
curl -X PUT http://localhost:8080/v1/user/email \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newemail@example.com"
  }'
```

---

### PUT /v1/user/password
**Update user's password**

**Authentication**: Bearer JWT (access token)

**Request Body**:
```json
{
  "old_password": "currentpassword123",
  "new_password": "newpassword456"
}
```

**Validation Rules**:
- `old_password`: Minimum 8 characters, maximum 256 characters
- `new_password`: Minimum 8 characters, maximum 256 characters

**Response (200)**:
```json
{
  "message": "Password updated"
}
```

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 400    | `INVALID_REQUEST_BODY` | Invalid request body         |
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 401    | `INVALID_CREDENTIALS`  | Invalid credentials          |
| 500    | `PASSWORD_HASH_FAILED` | Failed to hash password      |
| 500    | `INTERNAL_SERVER_ERROR`| Failed to update password    |

**Example cURL**:
```bash
curl -X PUT http://localhost:8080/v1/user/password \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "old_password": "currentpassword123",
    "new_password": "newpassword456"
  }'
```

---

## Settings Management

### GET /v1/settings/all
**Get all settings (both CW and Page settings) for current user**

**Authentication**: Bearer JWT (access token)

**Response (200)**:
```json
{
  "cw_settings": {
    "char_wpm": 20,
    "eff_wpm": 12,
    "freq": 600,
    "start_delay": 0.5,
    "updated_at": "2026-03-20T10:30:00Z"
  },
  "page_settings": {
    "language": "auto",
    "cur_lesson": 0,
    "updated_at": "2026-03-20T10:30:00Z"
  }
}
```

**Notes**: Returns default values if settings don't exist

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 500    | `SETTINGS_FETCH_FAILED`| Failed to get settings       |

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/settings/all \
  -H "Authorization: Bearer <access_token>"
```

---

### GET /v1/settings/cw
**Get CW (Morse Code) settings for current user**

**Authentication**: Bearer JWT (access token)

**Response (200)**:
```json
{
  "char_wpm": 20,
  "eff_wpm": 12,
  "freq": 600,
  "start_delay": 0.5,
  "updated_at": "2026-03-20T10:30:00Z"
}
```

**Default Values** (if not set):
- `char_wpm`: 20
- `eff_wpm`: 12
- `freq`: 600
- `start_delay`: 0.5

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 500    | `SETTINGS_FETCH_FAILED`| Failed to get settings       |

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/settings/cw \
  -H "Authorization: Bearer <access_token>"
```

---

### GET /v1/settings/page
**Get Page settings for current user**

**Authentication**: Bearer JWT (access token)

**Response (200)**:
```json
{
  "language": "auto",
  "cur_lesson": 0,
  "updated_at": "2026-03-20T10:30:00Z"
}
```

**Default Values** (if not set):
- `language`: "auto"
- `cur_lesson`: 0

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 500    | `SETTINGS_FETCH_FAILED`| Failed to get settings       |

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/settings/page \
  -H "Authorization: Bearer <access_token>"
```

---

### POST /v1/settings/cw
**Update CW (Morse Code) settings**

**Authentication**: Bearer JWT (access token)

**Request Body**:
```json
{
  "char_wpm": 25,
  "eff_wpm": 18,
  "freq": 700,
  "start_delay": 1.0
}
```

**Validation Rules**:
- `char_wpm`: Minimum 5, maximum 50
- `eff_wpm`: Minimum 5, maximum 50
- `freq`: Minimum 300, maximum 2000
- `start_delay`: Minimum 0.0, maximum 10.0

**Response (200)**:
```json
{
  "message": "Settings updated"
}
```

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 400    | `INVALID_REQUEST_BODY` | Invalid request body         |
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 500    | `SETTINGS_UPDATE_FAILED`| Failed to update settings   |

**Example cURL**:
```bash
curl -X POST http://localhost:8080/v1/settings/cw \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "char_wpm": 25,
    "eff_wpm": 18,
    "freq": 700,
    "start_delay": 1.0
  }'
```

---

### POST /v1/settings/page
**Update Page settings**

**Authentication**: Bearer JWT (access token)

**Request Body**:
```json
{
  "language": "en",
  "cur_lesson": 5
}
```

**Validation Rules**:
- `language`: Language code (custom validation)
- `cur_lesson`: Required integer

**Response (200)**:
```json
{
  "message": "Settings updated"
}
```

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 400    | `INVALID_REQUEST_BODY` | Invalid request body         |
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 500    | `SETTINGS_UPDATE_FAILED`| Failed to update settings   |

**Example cURL**:
```bash
curl -X POST http://localhost:8080/v1/settings/page \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "en",
    "cur_lesson": 5
  }'
```

---

## Progress Tracking

### GET /v1/cw/progress
**Get all Morse Code practice progress records for current user**

**Authentication**: Bearer JWT (access token)

**Response (200)**:
```json
{
  "data": [
    {
      "lesson": "1",
      "char_wpm": 20,
      "eff_wpm": 15,
      "accuracy": 0.95,
      "created_at": "2026-03-20T10:30:00Z",
      "client_created_at": "2026-03-20T10:25:00Z"
    },
    {
      "lesson": "2",
      "char_wpm": 22,
      "eff_wpm": 17,
      "accuracy": 0.97,
      "created_at": "2026-03-20T11:30:00Z",
      "client_created_at": "2026-03-20T11:25:00Z"
    }
  ]
}
```

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 500    | `PROGRESS_QUERY_FAILED`| Failed to query progress     |

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/cw/progress \
  -H "Authorization: Bearer <access_token>"
```

---

### PUT /v1/cw/progress
**Add or create a new progress record**

**Authentication**: Bearer JWT (access token)

**Request Body**:
```json
{
  "lesson": 1,
  "char_wpm": 20,
  "eff_wpm": 15,
  "accuracy": 0.95,
  "client_created_at": "2026-03-20T10:25:00Z"
}
```

**Validation Rules**:
- `lesson`: Required integer
- `char_wpm`: Minimum 5, maximum 50
- `eff_wpm`: Minimum 5, maximum 50
- `accuracy`: Minimum 0.0, maximum 1.0 (represents 0-100%)
- `client_created_at`: Optional ISO 8601 timestamp

**Response (201)**:
```json
{
  "message": "Progress Created"
}
```

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|------------------------|-------------------------------|
| 400    | `INVALID_REQUEST_BODY` | Invalid request body         |
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token     |
| 500    | `PROGRESS_CREATE_FAILED`| Failed to create progress   |

**Example cURL**:
```bash
curl -X PUT http://localhost:8080/v1/cw/progress \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "lesson": 1,
    "char_wpm": 20,
    "eff_wpm": 15,
    "accuracy": 0.95,
    "client_created_at": "2026-03-20T10:25:00Z"
  }'
```

---

## Forum

The forum is publicly readable. Creating a thread or reply requires an authenticated user with a **verified email** (`email_verified: true`); otherwise the API returns `403 EMAIL_NOT_VERIFIED`. Deleting requires an authenticated user who is the author of the thread/reply. Thread categories are a fixed set: `general`, `help`, `showcase`, `feedback`.

### GET /v1/forum/threads
**List forum threads, newest first (cursor paginated)**

**Authentication**: None

**Query Parameters**:
| Name     | Type    | Default | Description                                                   |
|----------|---------|---------|---------------------------------------------------------------|
| limit    | integer | 20      | Page size, 1-100                                              |
| cursor   | string  | -       | Opaque cursor taken from `next_cursor` of a previous response |
| category | string  | -       | Filter by one of `general`, `help`, `showcase`, `feedback`    |

**Response (200)**:
```json
{
  "data": [
    {
      "id": "0198c9d2-7f5e-7b1a-9c3e-1f2a3b4c5d6e",
      "category": "help",
      "title": "How do I improve my copy speed?",
      "author": {
        "username": "johndoe",
        "call_sign": "BG7ABC"
      },
      "reply_count": 3,
      "created_at": "2026-09-20T10:30:00Z"
    }
  ],
  "total": 137,
  "limit": 20,
  "next_cursor": "MjAyNi0wOS0yMFQxMDozMDowMFo..."
}
```

**Pagination**: pass `next_cursor` back as the `cursor` query parameter to fetch the next page. `next_cursor` is `null` when there are no more threads. `total` is the total count of threads matching the filter and is provided for display purposes.

**Error Responses**:
| Status | Error Code                | Message                                   |
|--------|---------------------------|-------------------------------------------|
| 400    | `INVALID_QUERY_PARAMETER` | Invalid query parameters / Invalid cursor |
| 500    | `FORUM_QUERY_FAILED`      | Failed to query forum threads             |

**Example cURL**:
```bash
curl -X GET "http://localhost:8080/v1/forum/threads?limit=20"
curl -X GET "http://localhost:8080/v1/forum/threads?limit=20&category=help"
curl -X GET "http://localhost:8080/v1/forum/threads?limit=20&cursor=<next_cursor>"
```

---

### GET /v1/forum/threads/:id
**Get a single forum thread**

**Authentication**: None

**Path Parameters**:
- `id`: Thread UUID

**Response (200)**:
```json
{
  "data": {
    "id": "0198c9d2-7f5e-7b1a-9c3e-1f2a3b4c5d6e",
    "category": "help",
    "title": "How do I improve my copy speed?",
    "body": "I can copy at 15 WPM but ...",
    "author": {
      "username": "johndoe",
      "call_sign": "BG7ABC"
    },
    "reply_count": 3,
    "created_at": "2026-09-20T10:30:00Z",
    "updated_at": "2026-09-20T10:30:00Z"
  }
}
```

**Error Responses**:
| Status | Error Code          | Message                      |
|--------|---------------------|------------------------------|
| 404    | `THREAD_NOT_FOUND`  | Thread not found             |
| 500    | `FORUM_QUERY_FAILED` | Failed to query forum thread |

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/forum/threads/<thread_id>
```

---

### GET /v1/forum/threads/:id/replies
**Get the full nested reply tree of a thread**

**Authentication**: None

**Path Parameters**:
- `id`: Thread UUID

Replies are returned chronologically (oldest first) as a nested tree: each reply may contain `children`. A soft-deleted reply that still has visible descendants is returned as a tombstone (`is_deleted: true`, with `body` and `author` set to `null`) so the thread structure is preserved; deleted replies without visible descendants are omitted. `total` counts the non-deleted replies.

**Response (200)**:
```json
{
  "data": [
    {
      "id": "0198c9d2-aaaa-7b1a-9c3e-1f2a3b4c5d6e",
      "parent_id": null,
      "body": "Top-level reply",
      "author": {
        "username": "jane",
        "call_sign": null
      },
      "is_deleted": false,
      "created_at": "2026-09-20T11:00:00Z",
      "children": [
        {
          "id": "0198c9d2-bbbb-7b1a-9c3e-1f2a3b4c5d6e",
          "parent_id": "0198c9d2-aaaa-7b1a-9c3e-1f2a3b4c5d6e",
          "body": "Nested reply",
          "author": {
            "username": "johndoe",
            "call_sign": "BG7ABC"
          },
          "is_deleted": false,
          "created_at": "2026-09-20T11:05:00Z",
          "children": []
        }
      ]
    }
  ],
  "total": 2
}
```

**Error Responses**:
| Status | Error Code           | Message                       |
|--------|----------------------|-------------------------------|
| 404    | `THREAD_NOT_FOUND`   | Thread not found              |
| 500    | `FORUM_QUERY_FAILED` | Failed to query forum replies |

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/forum/threads/<thread_id>/replies
```

---

### POST /v1/forum/threads
**Create a new forum thread**

**Authentication**: Bearer JWT (access token) + verified email

**Rate Limiting**: Five thread/reply creation attempts combined per verified user per rolling 60 seconds. Exceeded requests return `429 FORUM_RATE_LIMITED` with a `Retry-After` header containing seconds until the oldest attempt expires.

**Request Body**:
```json
{
  "category": "help",
  "title": "How do I improve my copy speed?",
  "body": "I can copy at 15 WPM but ..."
}
```

**Validation Rules**:
- `category`: Required, one of `general`, `help`, `showcase`, `feedback`
- `title`: Required, 3-200 characters
- `body`: Required, 1-10000 characters

**Response (201)**:
```json
{
  "data": {
    "id": "0198c9d2-7f5e-7b1a-9c3e-1f2a3b4c5d6e",
    "category": "help",
    "title": "How do I improve my copy speed?",
    "body": "I can copy at 15 WPM but ...",
    "author": {
      "username": "johndoe",
      "call_sign": "BG7ABC"
    },
    "reply_count": 0,
    "created_at": "2026-09-20T10:30:00Z",
    "updated_at": "2026-09-20T10:30:00Z"
  }
}
```

**Error Responses**:
| Status | Error Code              | Message                      |
|--------|-------------------------|------------------------------|
| 400    | `INVALID_REQUEST_BODY`  | Invalid request body         |
| 401    | `AUTH_HEADER_REQUIRED`  | Missing or invalid token     |
| 403    | `EMAIL_NOT_VERIFIED`    | Email verification required  |
| 429    | `FORUM_RATE_LIMITED`    | Please wait before creating another forum post |
| 500    | `FORUM_CREATE_FAILED`   | Failed to create forum thread |

**Example cURL**:
```bash
curl -X POST http://localhost:8080/v1/forum/threads \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "category": "help",
    "title": "How do I improve my copy speed?",
    "body": "I can copy at 15 WPM but ..."
  }'
```

---

### POST /v1/forum/threads/:id/replies
**Create a reply in a thread (optionally nested)**

**Authentication**: Bearer JWT (access token) + verified email

**Rate Limiting**: Five thread/reply creation attempts combined per verified user per rolling 60 seconds. Exceeded requests return `429 FORUM_RATE_LIMITED` with a `Retry-After` header containing seconds until the oldest attempt expires.

**Path Parameters**:
- `id`: Thread UUID

**Request Body**:
```json
{
  "body": "Try the Koch method at a slower character speed.",
  "parent_id": "0198c9d2-bbbb-7b1a-9c3e-1f2a3b4c5d6e"
}
```

`parent_id` is optional; when provided it must reference a live reply in the same thread.

**Validation Rules**:
- `body`: Required, 1-10000 characters
- `parent_id`: Optional reply UUID in the same thread

**Response (201)**:
```json
{
  "data": {
    "id": "0198c9d2-cccc-7b1a-9c3e-1f2a3b4c5d6e",
    "parent_id": "0198c9d2-bbbb-7b1a-9c3e-1f2a3b4c5d6e",
    "body": "Try the Koch method at a slower character speed.",
    "author": {
      "username": "jane",
      "call_sign": null
    },
    "is_deleted": false,
    "created_at": "2026-09-20T11:05:00Z",
    "children": []
  }
}
```

**Error Responses**:
| Status | Error Code              | Message                               |
|--------|-------------------------|---------------------------------------|
| 400    | `INVALID_REQUEST_BODY`  | Invalid request body                  |
| 400    | `REPLY_NOT_FOUND`       | Parent reply not found in this thread |
| 401    | `AUTH_HEADER_REQUIRED`  | Missing or invalid token              |
| 403    | `EMAIL_NOT_VERIFIED`    | Email verification required           |
| 404    | `THREAD_NOT_FOUND`      | Thread not found                      |
| 429    | `FORUM_RATE_LIMITED`    | Please wait before creating another forum post |
| 500    | `FORUM_CREATE_FAILED`   | Failed to create forum reply          |

**Example cURL**:
```bash
curl -X POST http://localhost:8080/v1/forum/threads/<thread_id>/replies \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{ "body": "Try the Koch method at a slower character speed." }'
```

---

### DELETE /v1/forum/threads/:id
**Soft-delete a thread (author only)**

**Authentication**: Bearer JWT (access token; must be the thread author)

**Path Parameters**:
- `id`: Thread UUID

**Response (200)**:
```json
{
  "message": "Thread deleted"
}
```

**Error Responses**:
| Status | Error Code             | Message                                |
|--------|------------------------|----------------------------------------|
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token               |
| 403    | `NOT_AUTHOR`           | Only the author can delete this thread |
| 404    | `THREAD_NOT_FOUND`     | Thread not found                       |
| 500    | `FORUM_DELETE_FAILED`  | Failed to delete forum thread          |

**Example cURL**:
```bash
curl -X DELETE http://localhost:8080/v1/forum/threads/<thread_id> \
  -H "Authorization: Bearer <access_token>"
```

---

### DELETE /v1/forum/replies/:id
**Soft-delete a reply (author only)**

**Authentication**: Bearer JWT (access token; must be the reply author)

**Path Parameters**:
- `id`: Reply UUID

**Response (200)**:
```json
{
  "message": "Reply deleted"
}
```

**Error Responses**:
| Status | Error Code             | Message                              |
|--------|------------------------|--------------------------------------|
| 401    | `AUTH_HEADER_REQUIRED` | Missing or invalid token             |
| 403    | `NOT_AUTHOR`           | Only the author can delete this reply |
| 404    | `REPLY_NOT_FOUND`      | Reply not found                      |
| 500    | `FORUM_DELETE_FAILED`  | Failed to delete forum reply         |

**Example cURL**:
```bash
curl -X DELETE http://localhost:8080/v1/forum/replies/<reply_id> \
  -H "Authorization: Bearer <access_token>"
```

---

## Error Handling

### Error Response Format

All error responses follow this format:

```json
{
  "code": "ERROR_CODE",
  "error": "Human readable error message"
}
```

### HTTP Status Codes

| Status | Meaning                |
|--------|------------------------|
| 200    | OK - Success           |
| 201    | Created                |
| 204    | No Content             |
| 400    | Bad Request            |
| 401    | Unauthorized           |
| 403    | Forbidden              |
| 404    | Not Found              |
| 409    | Conflict               |
| 429    | Too Many Requests      |
| 500    | Internal Server Error  |

### Common Error Codes

| Error Code                      | HTTP Status | Meaning                                   |
|---------------------------------|------------|-------------------------------------------|
| `INVALID_REQUEST_BODY`          | 400        | Request body is malformed or missing      |
| `INVALID_CREDENTIALS`           | 401        | Username/email or password is incorrect   |
| `AUTH_HEADER_REQUIRED`          | 401        | Missing Authorization header              |
| `INVALID_AUTH_HEADER_FORMAT`    | 401        | Authorization header format is invalid    |
| `INVALID_TOKEN`                 | 401        | Token is invalid or malformed             |
| `EXPIRED_TOKEN`                 | 401        | Token has expired                         |
| `DATABASE_FAILURE`              | 500        | Database operation failed                 |
| `INTERNAL_SERVER_ERROR`         | 500        | Unexpected server error                   |
| `CONFLICT`                      | 409        | Resource conflict (generic)               |
| `USER_NOT_FOUND`                | 404        | User does not exist                       |
| `USERNAME_ALREADY_IN_USE`       | 409        | Username is taken                         |
| `EMAIL_ALREADY_IN_USE`          | 409        | Email is already in use                   |
| `EMAIL_VERIFIED_BY_ANOTHER_ACCOUNT` | 409    | Email verified by another user            |
| `EMAIL_UNCHANGED`               | 400        | New email is same as current              |
| `EMAIL_ALREADY_VERIFIED`        | 400        | Email is already verified                 |
| `CALL_SIGN_ALREADY_IN_USE`      | 409        | Call sign is taken                        |
| `PASSWORD_HASH_FAILED`          | 500        | Failed to hash password                   |
| `TOKEN_ISSUE_FAILED`            | 500        | Failed to issue JWT token                 |
| `VERIFICATION_CODE_INVALID`     | 400        | Verification code is invalid              |
| `VERIFICATION_CODE_EXPIRED`     | 400        | Verification code has expired             |
| `VERIFICATION_SEND_FAILED`      | 500        | Failed to send verification email         |
| `VERIFICATION_RATE_LIMITED`     | 429        | Too many verification requests            |
| `SETTINGS_FETCH_FAILED`         | 500        | Failed to retrieve settings               |
| `SETTINGS_UPDATE_FAILED`        | 500        | Failed to update settings                 |
| `PROGRESS_QUERY_FAILED`         | 500        | Failed to query progress records          |
| `PROGRESS_CREATE_FAILED`        | 500        | Failed to create progress record          |
| `EMAIL_NOT_VERIFIED`            | 403        | Email verification required for posting   |
| `INVALID_QUERY_PARAMETER`       | 400        | Invalid query parameter or cursor         |
| `THREAD_NOT_FOUND`              | 404        | Forum thread does not exist               |
| `REPLY_NOT_FOUND`               | 404        | Forum reply (or parent reply) not found   |
| `NOT_AUTHOR`                    | 403        | Only the author may delete this content   |
| `FORUM_QUERY_FAILED`            | 500        | Failed to query forum content             |
| `FORUM_CREATE_FAILED`           | 500        | Failed to create forum content            |
| `FORUM_DELETE_FAILED`           | 500        | Failed to delete forum content            |

### Authentication

All endpoints marked with "Auth Required" use Bearer token authentication:

```
Authorization: Bearer <access_token>
```

Replace `<access_token>` with the JWT token received from the login or register endpoints.

### CORS

The API supports CORS with the following configuration:
- **Development Mode**: All origins allowed
- **Production Mode**: Only `https://opencw.net` allowed (unless `CORS_ORIGINS` env var is set)

CORS headers included in responses:
- `Access-Control-Allow-Origin`: Allowed origin
- `Access-Control-Allow-Credentials`: true
- `Access-Control-Allow-Methods`: GET, POST, PUT, DELETE, OPTIONS
- `Access-Control-Allow-Headers`: Origin, Content-Type, Authorization

---

## Test Authenticated Endpoint

### GET /v1/hello
**Test endpoint to verify authentication is working**

**Authentication**: Bearer JWT (access token)

**Response (200)**:
```json
{
  "message": "Hello, authenticated user {username}!"
}
```

**Example cURL**:
```bash
curl -X GET http://localhost:8080/v1/hello \
  -H "Authorization: Bearer <access_token>"
```

---

## Implementation Notes

### Environment Variables
- `GIN_MODE`: Set to "release" for production mode
- `CORS_ORIGINS`: Comma-separated list of allowed origins (optional, production only)

### Database
The API uses GORM with support for cascading deletes. When a user is deleted, all associated settings and progress records are automatically deleted.

### Token Expiration
- Access tokens have a shorter expiration time (typically minutes)
- Refresh tokens have a longer expiration time (typically days)
- Use the refresh endpoint to get a new access token when it expires

### Refresh Token Cleanup
Background process automatically cleans up expired and revoked refresh tokens every 3 hours.

