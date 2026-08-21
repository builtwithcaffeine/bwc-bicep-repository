# Galactic sci-fi custom status pages

Brand-safe, space-opera inspired custom status pages for Azure Application Gateway.

> These pages intentionally avoid official names, logos, characters, quotes, and other protected franchise elements. They provide a generic galactic sci-fi look and feel suitable for testing or internal demos.

## Status code mapping

| Status code | Azure portal label | File |
| --- | --- | --- |
| 400 | Bad request | `400-bad-request.html` |
| 403 | Forbidden | `403-forbidden.html` |
| 405 | Method not allowed | `405-method-not-allowed.html` |
| 408 | Request timeout | `408-request-timeout.html` |
| 500 | Internal Server Error | `500-internal-server-error.html` |
| 502 | Bad Gateway | `502-bad-gateway.html` |
| 503 | Service Unavailable | `503-service-unavailable.html` |
| 504 | Gateway timeout | `504-gateway-timeout.html` |

## Hosting note

Application Gateway custom error page settings expect URLs to HTML files. Host these files from a publicly reachable HTTPS endpoint, such as Azure Storage static website hosting, Azure Static Web Apps, or a CDN-backed origin, then paste each file URL into the matching Application Gateway custom error page setting.

The pages are standalone and include inline CSS so they do not depend on external assets.
