//! Requête/réponse HTTP internes et petits utilitaires partagés.
//!
//! Le routage reproduit la `Cascade` shelf de l'ancien serveur : chaque
//! étage (API, proxy Xtream, streaming, fichiers statiques) répond ou passe
//! la main par un 404/405. Le corps des requêtes est lu une fois pour toutes
//! en amont, ce qui permet de présenter la même requête à plusieurs étages.

use crate::models::User;
use axum::body::Body;
use axum::http::{HeaderMap, HeaderName, HeaderValue, Method, StatusCode};
use bytes::Bytes;
use serde_json::Value;
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};

pub type Resp = axum::response::Response;

#[derive(Clone)]
pub struct Req {
    pub method: Method,
    /// Chemin sans `/` initial, tel que reçu (encodé), comme `request.url.path`.
    pub path: String,
    /// Query string brute, sans `?`.
    pub query: String,
    pub headers: HeaderMap,
    pub body: Bytes,
    pub remote: Option<SocketAddr>,
    /// Renseignés par le middleware d'authentification.
    pub user: Option<User>,
    pub user_id: Option<String>,
}

impl Req {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.get(name).and_then(|v| v.to_str().ok())
    }

    /// Paramètres de query décodés (`+` = espace) ; la dernière occurrence
    /// d'une clé l'emporte, comme `Uri.queryParameters`.
    pub fn query_params(&self) -> HashMap<String, String> {
        url::form_urlencoded::parse(self.query.as_bytes())
            .into_owned()
            .collect()
    }

    pub fn query_param(&self, key: &str) -> Option<String> {
        self.query_params().remove(key)
    }

    pub fn is_get(&self) -> bool {
        self.method == Method::GET || self.method == Method::HEAD
    }

    pub fn body_str(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }
}

// ==================== Réponses ====================

pub fn response(status: u16, body: impl Into<Body>) -> Resp {
    let mut resp = Resp::new(body.into());
    *resp.status_mut() = StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    resp
}

/// Corps texte (`text/plain; charset=utf-8`, le défaut de shelf).
pub fn text(status: u16, body: impl Into<String>) -> Resp {
    let mut resp = response(status, body.into());
    set_header(&mut resp, "content-type", "text/plain; charset=utf-8");
    resp
}

pub fn empty(status: u16) -> Resp {
    response(status, Body::empty())
}

/// JSON avec l'en-tête `Content-Type: application/json`.
pub fn json(status: u16, value: &Value) -> Resp {
    raw_json(status, value.to_string())
}

pub fn raw_json(status: u16, body: String) -> Resp {
    let mut resp = response(status, body);
    set_header(&mut resp, "content-type", "application/json");
    resp
}

/// JSON sans en-tête de type (les `Response.forbidden(jsonEncode(...))` de
/// l'ancien serveur, servis en `text/plain`).
pub fn json_as_text(status: u16, value: &Value) -> Resp {
    text(status, value.to_string())
}

pub fn redirect(location: &str) -> Resp {
    let mut resp = text(302, format!("Moved to {location}"));
    set_header(&mut resp, "location", location);
    resp
}

pub fn set_header(resp: &mut Resp, name: &str, value: &str) {
    if let (Ok(name), Ok(value)) = (
        HeaderName::from_bytes(name.as_bytes()),
        HeaderValue::from_str(value),
    ) {
        resp.headers_mut().insert(name, value);
    }
}

pub fn with_headers(mut resp: Resp, headers: &[(&str, &str)]) -> Resp {
    for (name, value) in headers {
        set_header(&mut resp, name, value);
    }
    resp
}

/// La `Cascade` passe à l'étage suivant sur un 404 ou un 405.
pub fn is_miss(resp: &Resp) -> bool {
    matches!(resp.status().as_u16(), 404 | 405)
}

pub fn not_found() -> Resp {
    text(404, "Not Found")
}

// ==================== Authentification ====================

/// Jeton de session : en-tête `Authorization: Bearer …` ou cookie `session`.
pub fn extract_token(req: &Req) -> Option<String> {
    if let Some(auth) = req.header("authorization")
        && let Some(token) = auth.strip_prefix("Bearer ")
    {
        return Some(token.to_string());
    }
    let cookie = req.header("cookie")?;
    cookie
        .split(';')
        .map(str::trim)
        .find_map(|part| part.strip_prefix("session=").map(str::to_string))
}

// ==================== Adresse du client ====================

/// Proxys de confiance dont l'en-tête X-Forwarded-For est honoré :
/// TRUSTED_PROXIES, IP ou plages CIDR séparées par des virgules
/// (ex. `172.18.0.0/16`). VIDE PAR DÉFAUT : aucun proxy n'est cru sur parole.
/// Faire confiance d'office à tout le RFC1918 laissait n'importe quel client
/// du LAN (ou d'un réseau Docker voisin) forger X-Forwarded-For pour
/// contourner le rate limit et la limite de tentatives de login.
pub fn is_trusted_proxy(address: &IpAddr, trusted: &[String]) -> bool {
    let address = unmap(*address);
    trusted
        .iter()
        .any(|entry| proxy_entry_matches(address, entry))
}

/// IPv4 « nue » pour une adresse IPv4 mappée en IPv6.
fn unmap(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => v6
            .to_ipv4_mapped()
            .map(IpAddr::V4)
            .unwrap_or(IpAddr::V6(v6)),
        ip => ip,
    }
}

fn proxy_entry_matches(address: IpAddr, entry: &str) -> bool {
    let entry = entry.trim();
    let Some((net, len)) = entry.split_once('/') else {
        return entry.parse::<IpAddr>().is_ok_and(|ip| unmap(ip) == address);
    };
    let (Ok(net), Ok(len)) = (net.trim().parse::<IpAddr>(), len.trim().parse::<u32>()) else {
        return false;
    };
    match (unmap(net), address) {
        (IpAddr::V4(n), IpAddr::V4(a)) if len <= 32 => {
            let mask = u32::MAX.checked_shl(32 - len).unwrap_or(0);
            u32::from(n) & mask == u32::from(a) & mask
        }
        (IpAddr::V6(n), IpAddr::V6(a)) if len <= 128 => {
            let mask = u128::MAX.checked_shl(128 - len).unwrap_or(0);
            u128::from(n) & mask == u128::from(a) & mask
        }
        _ => false,
    }
}

/// Adresse socket au format texte (IPv4 « nue » pour les adresses mappées).
pub fn socket_ip(req: &Req) -> Option<IpAddr> {
    req.remote.map(|addr| match addr.ip() {
        IpAddr::V6(v6) => v6
            .to_ipv4_mapped()
            .map(IpAddr::V4)
            .unwrap_or(IpAddr::V6(v6)),
        ip => ip,
    })
}

/// IP réelle du client.
///
/// X-Forwarded-For n'est honoré que si la connexion socket provient d'un
/// proxy de confiance : sinon un client direct peut forger l'en-tête et
/// contourner le rate limit global comme la limite de tentatives de login.
/// L'en-tête est lu de DROITE à gauche : chaque proxy ajoute l'adresse de son
/// interlocuteur à la fin, seules les entrées de droite sont donc fiables. La
/// première qui n'est pas un proxy de confiance est le client ; ce que le
/// client a lui-même écrit à gauche est ignoré.
pub fn client_ip(req: &Req, trusted: &[String]) -> String {
    let socket = socket_ip(req);
    if let (Some(forwarded), Some(ip)) = (req.header("x-forwarded-for"), socket)
        && is_trusted_proxy(&ip, trusted)
    {
        for hop in forwarded
            .rsplit(',')
            .map(str::trim)
            .filter(|h| !h.is_empty())
        {
            match hop.parse::<IpAddr>() {
                Ok(hop) if is_trusted_proxy(&hop, trusted) => continue,
                Ok(hop) => return unmap(hop).to_string(),
                // Entrée illisible : la chaîne n'est plus fiable au-delà.
                Err(_) => break,
            }
        }
    }
    socket
        .map(|ip| ip.to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

/// Segments d'un sous-chemin monté (`""` → aucun segment).
pub fn segments(rest: &str) -> Vec<&str> {
    let rest = rest.trim_start_matches('/');
    if rest.is_empty() {
        Vec::new()
    } else {
        rest.split('/').collect()
    }
}

/// Sous-chemin d'un montage shelf (`mount('/api/x')`) : `Some("")` pour
/// `api/x` ou `api/x/`, `Some("a/b")` pour `api/x/a/b`, `None` sinon.
pub fn mounted<'a>(path: &'a str, prefix: &str) -> Option<&'a str> {
    if path == prefix {
        return Some("");
    }
    path.strip_prefix(prefix)?.strip_prefix('/')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req_with(headers: &[(&str, &str)], remote: &str) -> Req {
        let mut map = HeaderMap::new();
        for (k, v) in headers {
            map.insert(
                HeaderName::from_bytes(k.as_bytes()).unwrap(),
                HeaderValue::from_str(v).unwrap(),
            );
        }
        Req {
            method: Method::GET,
            path: String::new(),
            query: String::new(),
            headers: map,
            body: Bytes::new(),
            remote: Some(remote.parse().unwrap()),
            user: None,
            user_id: None,
        }
    }

    #[test]
    fn jeton_par_en_tete_ou_cookie() {
        assert_eq!(
            extract_token(&req_with(&[("authorization", "Bearer abc")], "1.2.3.4:1")),
            Some("abc".into())
        );
        assert_eq!(
            extract_token(&req_with(
                &[("cookie", "a=1; session=xyz; b=2")],
                "1.2.3.4:1"
            )),
            Some("xyz".into())
        );
        assert_eq!(extract_token(&req_with(&[], "1.2.3.4:1")), None);
    }

    #[test]
    fn x_forwarded_for_seulement_derriere_un_proxy_de_confiance() {
        let direct = req_with(&[("x-forwarded-for", "9.9.9.9")], "8.8.8.8:1");
        assert_eq!(client_ip(&direct, &[]), "8.8.8.8");
        // Défaut : aucun proxy de confiance, même sur le LAN ou en loopback.
        let proxied = req_with(&[("x-forwarded-for", "9.9.9.9")], "172.18.0.2:1");
        assert_eq!(client_ip(&proxied, &[]), "172.18.0.2");
        let local = req_with(&[("x-forwarded-for", "9.9.9.9")], "127.0.0.1:1");
        assert_eq!(client_ip(&local, &[]), "127.0.0.1");
        assert_eq!(client_ip(&proxied, &["10.1.1.1".into()]), "172.18.0.2");
        assert_eq!(client_ip(&proxied, &["172.18.0.2".into()]), "9.9.9.9");
        assert_eq!(client_ip(&proxied, &["172.18.0.0/16".into()]), "9.9.9.9");
    }

    #[test]
    fn x_forwarded_for_lu_de_droite_a_gauche() {
        let trusted = vec!["172.18.0.0/16".to_string(), "10.0.0.1".to_string()];
        // Le client forge « 127.0.0.1 » à gauche ; le proxy ajoute sa vraie IP.
        let spoofed = req_with(
            &[("x-forwarded-for", "127.0.0.1, 203.0.113.7")],
            "172.18.0.2:1",
        );
        assert_eq!(client_ip(&spoofed, &trusted), "203.0.113.7");
        // Deux proxys de confiance enchaînés : ils sont sautés.
        let chain = req_with(
            &[("x-forwarded-for", "1.2.3.4, 203.0.113.7, 10.0.0.1")],
            "172.18.0.2:1",
        );
        assert_eq!(client_ip(&chain, &trusted), "203.0.113.7");
        // Entrée illisible : repli sur l'adresse socket.
        let junk = req_with(&[("x-forwarded-for", "nimporte")], "172.18.0.2:1");
        assert_eq!(client_ip(&junk, &trusted), "172.18.0.2");
    }

    #[test]
    fn proxys_de_confiance_cidr() {
        let ip = |s: &str| s.parse::<IpAddr>().unwrap();
        let t = vec![
            "10.0.0.0/8".to_string(),
            "fd00::/8".to_string(),
            "192.168.1.5".to_string(),
        ];
        assert!(is_trusted_proxy(&ip("10.200.1.1"), &t));
        assert!(is_trusted_proxy(&ip("::ffff:10.0.0.1"), &t));
        assert!(is_trusted_proxy(&ip("fd12::1"), &t));
        assert!(is_trusted_proxy(&ip("192.168.1.5"), &t));
        assert!(!is_trusted_proxy(&ip("192.168.1.6"), &t));
        assert!(!is_trusted_proxy(&ip("11.0.0.1"), &t));
        assert!(!is_trusted_proxy(&ip("127.0.0.1"), &[]));
        assert!(is_trusted_proxy(&ip("1.2.3.4"), &["0.0.0.0/0".into()]));
    }

    #[test]
    fn montage_shelf() {
        assert_eq!(mounted("api/playlists", "api/playlists"), Some(""));
        assert_eq!(mounted("api/playlists/", "api/playlists"), Some(""));
        assert_eq!(mounted("api/playlists/x", "api/playlists"), Some("x"));
        assert_eq!(mounted("api/playlistsx", "api/playlists"), None);
    }

    #[test]
    fn parametres_de_query() {
        let mut req = req_with(&[], "1.2.3.4:1");
        req.query = "a=1&b=x+y&a=2&c=%C3%A9".into();
        let params = req.query_params();
        assert_eq!(params["a"], "2");
        assert_eq!(params["b"], "x y");
        assert_eq!(params["c"], "é");
    }
}
