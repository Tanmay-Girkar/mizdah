import '../config/api_config.dart';

/// Resolve a media URL the backend may have returned as a *relative*
/// path against the gateway base URL.
///
/// The file-service "Edit Profile — Flutter Integration Guide" (§2)
/// is explicit: in production the upload endpoint returns a
/// Cloudflare R2 absolute URL, but in dev (R2 not configured) it
/// returns the relative form `/api/file/uploads/<filename>` served
/// by the file-service itself. `Image.network` can't render that —
/// it tries to GET a path that has no scheme, the request silently
/// fails, and the avatar falls back to the initial.
///
/// Behaviour:
///
///   - `null`     → `null`
///   - empty/ws   → `null`
///   - `http://…` / `https://…` (already absolute) → returned as-is
///   - `data:` / `blob:` (in-memory)              → returned as-is
///   - `/path/x` (relative) → `<baseUrl>/path/x`
///   - `path/x` (no leading slash, treat as relative to baseUrl)
///                          → `<baseUrl>/path/x`
String? resolveMediaUrl(String? raw) {
  if (raw == null) return null;
  final v = raw.trim();
  if (v.isEmpty) return null;
  final lower = v.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('data:') ||
      lower.startsWith('blob:')) {
    return v;
  }
  // Strip any trailing slash on baseUrl so we don't end up with `//`.
  final base = ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;
  if (v.startsWith('/')) return '$base$v';
  return '$base/$v';
}
