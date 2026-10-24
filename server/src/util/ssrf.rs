//! Protection SSRF des appels sortants dont l'URL vient d'un client
//! (proxy `/api/xtream/<url>`, URL de flux des enregistrements).
//!
//! Vérifier le NOM d'hôte ne suffit pas : `picons.attaquant.tld` peut se
//! résoudre en `127.0.0.1` ou `169.254.169.254`, et changer de réponse entre
//! la vérification et la connexion (DNS rebinding). Le contrôle se fait donc
//! sur CHAQUE adresse résolue, au moment de la connexion, par un résolveur
//! DNS dédié branché dans le client reqwest ([`GuardedResolver`]).
//!
//! Échappatoire : `PROXY_ALLOW_PRIVATE_HOSTS` (noms d'hôtes séparés par des
//! virgules) autorise explicitement des hôtes du réseau local — un panneau
//! IPTV hébergé sur le LAN, par exemple. Le résolveur admet aussi le nom des
//! proxys HTTP sortants (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`) : c'est ce
//! nom que le client résout quand il passe par eux.

use reqwest::dns::{Addrs, Name, Resolve, Resolving};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

/// Adresse à ne jamais atteindre depuis une URL fournie par un client :
/// non routable, loopback, réseau privé, link-local (dont les métadonnées
/// cloud 169.254.169.254), CGNAT, multicast, réservé — y compris sous forme
/// IPv6 (adresses IPv4 mappées, compatibles, NAT64).
pub fn is_forbidden_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => is_forbidden_v4(v4),
        IpAddr::V6(v6) => is_forbidden_v6(v6),
    }
}

fn is_forbidden_v4(v4: Ipv4Addr) -> bool {
    let o = v4.octets();
    o[0] == 0 // « ce réseau », dont 0.0.0.0
        || v4.is_loopback() // 127/8
        || v4.is_private() // 10/8, 172.16/12, 192.168/16
        || v4.is_link_local() // 169.254/16 (métadonnées cloud)
        || (o[0] == 100 && (o[1] & 0xc0) == 64) // CGNAT 100.64/10
        || (o[0] == 192 && o[1] == 0 && o[2] == 0) // 192.0.0/24
        || (o[0] == 198 && (o[1] & 0xfe) == 18) // bancs d'essai 198.18/15
        || v4.is_multicast() // 224/4
        || o[0] >= 240 // réservé + diffusion
}

fn is_forbidden_v6(v6: Ipv6Addr) -> bool {
    if let Some(v4) = v6.to_ipv4_mapped() {
        return is_forbidden_v4(v4); // ::ffff:a.b.c.d
    }
    let s = v6.segments();
    // ::a.b.c.d (IPv4 compatible, obsolète) et NAT64 64:ff9b::/96.
    if (s[..6] == [0, 0, 0, 0, 0, 0] && !v6.is_unspecified() && !v6.is_loopback())
        || s[..6] == [0x64, 0xff9b, 0, 0, 0, 0]
    {
        let [a, b] = s[6].to_be_bytes();
        let [c, d] = s[7].to_be_bytes();
        return is_forbidden_v4(Ipv4Addr::new(a, b, c, d));
    }
    v6.is_unspecified()
        || v6.is_loopback()
        || (s[0] & 0xfe00) == 0xfc00 // unique-local fc00::/7
        || (s[0] & 0xffc0) == 0xfe80 // link-local fe80::/10
        || (s[0] & 0xffc0) == 0xfec0 // site-local fec0::/10 (obsolète)
        || v6.is_multicast()
}

/// Hôte (tel qu'écrit dans l'URL) visiblement interdit, sans résolution DNS :
/// `localhost` et ses sous-domaines, ou adresse IP littérale interdite. Les
/// autres noms sont jugés à la connexion par [`GuardedResolver`].
pub fn is_forbidden_host_literal(host: &str) -> bool {
    let lower = host.to_lowercase();
    let lower = lower
        .trim_start_matches('[')
        .trim_end_matches(']')
        .trim_end_matches('.');
    if lower == "localhost" || lower.ends_with(".localhost") {
        return true;
    }
    lower.parse::<IpAddr>().is_ok_and(is_forbidden_ip)
}

/// Noms d'hôtes admis malgré une adresse privée (PROXY_ALLOW_PRIVATE_HOSTS).
fn private_allowlist_from_env() -> Vec<String> {
    std::env::var("PROXY_ALLOW_PRIVATE_HOSTS")
        .unwrap_or_default()
        .split(',')
        .map(|h| h.trim().trim_end_matches('.').to_lowercase())
        .filter(|h| !h.is_empty())
        .collect()
}

/// Noms des proxys HTTP sortants : quand reqwest passe par l'un d'eux, c'est
/// SON nom qu'il fait résoudre. Admis par le résolveur seulement — jamais
/// comme destination d'une URL vérifiée par [`GuardedResolver::check_url`].
fn outbound_proxy_hosts_from_env() -> Vec<String> {
    let mut hosts = Vec::new();
    for var in [
        "HTTP_PROXY",
        "http_proxy",
        "HTTPS_PROXY",
        "https_proxy",
        "ALL_PROXY",
        "all_proxy",
    ] {
        if let Some(host) = std::env::var(var)
            .ok()
            .and_then(|v| url::Url::parse(&v).ok())
            .and_then(|u| u.host_str().map(str::to_lowercase))
        {
            hosts.push(host);
        }
    }
    hosts
}

/// Résolveur DNS qui refuse tout nom dont une adresse est interdite.
///
/// Appelé par reqwest à chaque nouvelle connexion (redirections comprises) :
/// l'adresse contrôlée est celle à laquelle on se connecte réellement.
pub struct GuardedResolver {
    allow_private: Vec<String>,
    proxy_hosts: Vec<String>,
}

impl GuardedResolver {
    pub fn from_env() -> Self {
        Self {
            allow_private: private_allowlist_from_env(),
            proxy_hosts: outbound_proxy_hosts_from_env(),
        }
    }

    fn allows_private(&self, host: &str) -> bool {
        let host = host.trim_end_matches('.').to_lowercase();
        self.allow_private.contains(&host)
    }

    /// Adresses publiques de `host`, ou erreur si l'une d'elles est interdite.
    pub async fn resolve_public(&self, host: &str, port: u16) -> Result<Vec<SocketAddr>, String> {
        let addrs: Vec<SocketAddr> = tokio::net::lookup_host((host, port))
            .await
            .map_err(|e| format!("résolution de {host} impossible : {e}"))?
            .collect();
        if addrs.is_empty() {
            return Err(format!("aucune adresse pour {host}"));
        }
        if !self.allows_private(host) && addrs.iter().any(|a| is_forbidden_ip(a.ip())) {
            println!("[SSRF] Hôte {host} refusé : adresse privée ou réservée");
            return Err(format!("accès à l'hôte {host} interdit"));
        }
        Ok(addrs)
    }

    /// URL fournie par un client, sûre à passer à un outil qui fait sa propre
    /// résolution (FFmpeg) : http(s) seulement, hôte public.
    pub async fn check_url(&self, raw: &str) -> Result<url::Url, String> {
        let url = url::Url::parse(raw).map_err(|_| "URL invalide".to_string())?;
        if url.scheme() != "http" && url.scheme() != "https" {
            return Err("seules les URL http(s) sont acceptées".into());
        }
        let host = url
            .host_str()
            .filter(|h| !h.is_empty())
            .ok_or_else(|| "URL sans hôte".to_string())?
            .trim_start_matches('[')
            .trim_end_matches(']')
            .to_string();
        if self.allows_private(&host) {
            return Ok(url);
        }
        if is_forbidden_host_literal(&host) {
            return Err(format!("accès à l'hôte {host} interdit"));
        }
        if host.parse::<IpAddr>().is_err() {
            let port = url.port_or_known_default().unwrap_or(80);
            self.resolve_public(&host, port).await?;
        }
        Ok(url)
    }
}

/// URL de flux d'un enregistrement, contrôlée SANS résolution DNS (routes
/// synchrones) : chemin local `/api/…` (relayé par ce serveur), ou URL
/// http(s) dont l'hôte n'est pas visiblement interne. Tout le reste —
/// `file:`, `concat:`, options FFmpeg… — est refusé : la valeur finit en
/// argument `-i` de FFmpeg.
pub fn check_stream_url_syntax(raw: &str) -> Result<(), String> {
    let raw = raw.trim();
    if raw.chars().any(char::is_control) {
        return Err("stream_url invalide".into());
    }
    if raw.starts_with('/') {
        if raw.starts_with("/api/") && !raw.contains("..") {
            return Ok(());
        }
        return Err("stream_url locale invalide (attendu /api/…)".into());
    }
    let url = url::Url::parse(raw).map_err(|_| "stream_url invalide".to_string())?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err("stream_url : seules les URL http(s) sont acceptées".into());
    }
    match url.host_str() {
        Some(h) if !h.is_empty() => {
            if is_forbidden_host_literal(h) && !GuardedResolver::from_env().allows_private(h) {
                return Err(format!("stream_url : accès à l'hôte {h} interdit"));
            }
            Ok(())
        }
        _ => Err("stream_url sans hôte".into()),
    }
}

/// Contrôle complet d'une URL de flux : syntaxe, puis, pour une URL absolue,
/// chaque adresse résolue de son hôte. Refait au lancement de FFmpeg, qui
/// résout le nom lui-même.
pub async fn check_stream_url(raw: &str) -> Result<(), String> {
    check_stream_url_syntax(raw)?;
    if raw.trim().starts_with('/') {
        return Ok(());
    }
    GuardedResolver::from_env()
        .check_url(raw.trim())
        .await
        .map(|_| ())
}

impl Resolve for GuardedResolver {
    fn resolve(&self, name: Name) -> Resolving {
        let host = name.as_str().to_string();
        let mut allow_private = self.allow_private.clone();
        allow_private.extend(self.proxy_hosts.iter().cloned());
        let guard = GuardedResolver {
            allow_private,
            proxy_hosts: Vec::new(),
        };
        Box::pin(async move {
            let addrs = guard
                .resolve_public(&host, 0)
                .await
                .map_err(|e| -> Box<dyn std::error::Error + Send + Sync> { e.into() })?;
            Ok(Box::new(addrs.into_iter()) as Addrs)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    #[test]
    fn plages_interdites() {
        for s in [
            "0.0.0.0",
            "127.0.0.1",
            "127.255.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "172.31.255.255",
            "192.168.1.1",
            "169.254.169.254",
            "100.64.0.1",
            "100.127.255.255",
            "192.0.0.170",
            "198.18.0.1",
            "224.0.0.1",
            "255.255.255.255",
            "::",
            "::1",
            "fc00::1",
            "fd12:3456::1",
            "fe80::1",
            "fec0::1",
            "ff02::1",
            "::ffff:127.0.0.1",
            "::ffff:169.254.169.254",
            "::ffff:10.0.0.1",
            "::127.0.0.1",
            "64:ff9b::a9fe:a9fe",
        ] {
            assert!(is_forbidden_ip(ip(s)), "{s} devrait être interdit");
        }
    }

    #[test]
    fn adresses_publiques_admises() {
        for s in [
            "8.8.8.8",
            "1.1.1.1",
            "172.32.0.1",
            "100.128.0.1",
            "192.0.2.1",
            "2606:4700:4700::1111",
            "::ffff:8.8.8.8",
            "64:ff9b::808:808",
        ] {
            assert!(!is_forbidden_ip(ip(s)), "{s} devrait être admis");
        }
    }

    #[test]
    fn litteraux() {
        assert!(is_forbidden_host_literal("localhost"));
        assert!(is_forbidden_host_literal("LOCALHOST."));
        assert!(is_forbidden_host_literal("x.localhost"));
        assert!(is_forbidden_host_literal("[::1]"));
        assert!(is_forbidden_host_literal("[::ffff:7f00:1]"));
        assert!(!is_forbidden_host_literal("cdn.example.com"));
        assert!(!is_forbidden_host_literal("8.8.8.8"));
    }

    #[tokio::test]
    async fn verification_d_url() {
        let g = GuardedResolver {
            allow_private: vec!["panel.lan".into()],
            proxy_hosts: vec![],
        };
        assert!(g.check_url("file:///etc/passwd").await.is_err());
        assert!(g.check_url("concat:a|b").await.is_err());
        assert!(g.check_url("http://127.0.0.1:8089/x").await.is_err());
        assert!(g.check_url("http://2130706433/").await.is_err());
        assert!(g.check_url("http://[::ffff:a9fe:a9fe]/").await.is_err());
        assert!(g.check_url("http://localhost/").await.is_err());
        assert!(g.check_url("http://8.8.8.8/live.ts").await.is_ok());
        // Hôte privé explicitement autorisé : pas même résolu.
        assert!(g.check_url("http://panel.lan:8080/live.ts").await.is_ok());
    }

    #[tokio::test]
    async fn url_de_flux() {
        assert!(
            check_stream_url("/api/live/12.ts?playlist=ab")
                .await
                .is_ok()
        );
        assert!(
            check_stream_url("http://8.8.8.8/live/u/p/12.ts")
                .await
                .is_ok()
        );
        for bad in [
            "/etc/passwd",
            "/api/../etc/passwd",
            "file:///etc/passwd",
            "concat:/a|/b",
            "-f lavfi",
            "http://127.0.0.1:8089/api/xtream/x",
            "http://169.254.169.254/latest/meta-data/",
            "http://[::ffff:10.0.0.1]/x",
            "http://localhost/x",
            "gopher://8.8.8.8/",
            "/api/live/1.ts\nx",
        ] {
            assert!(
                check_stream_url(bad).await.is_err(),
                "{bad} devrait être refusée"
            );
        }
    }

    #[tokio::test]
    async fn resolveur_refuse_le_loopback() {
        let g = GuardedResolver {
            allow_private: vec![],
            proxy_hosts: vec![],
        };
        assert!(g.resolve_public("localhost", 80).await.is_err());
        let ok = GuardedResolver {
            allow_private: vec!["localhost".into()],
            proxy_hosts: vec![],
        };
        assert!(ok.resolve_public("localhost", 80).await.is_ok());
    }
}
