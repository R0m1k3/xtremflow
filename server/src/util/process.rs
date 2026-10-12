//! Processus enfants (FFmpeg) pilotés par signal.
//!
//! POURQUOI : `tokio::process::Child::kill` envoie SIGKILL. FFmpeg tué ainsi
//! ne finalise pas son fichier (index MKV absent, playlist HLS sans fin) :
//! l'ancien serveur envoyait SIGTERM, que FFmpeg traite comme un arrêt
//! propre. Le processus est donc confié à une tâche qui attend sa fin et
//! relaie les demandes d'arrêt sous forme de vrais signaux.

use tokio::process::Child;
use tokio::sync::{mpsc, watch};

#[derive(Clone, Copy, Debug)]
enum Signal {
    Term,
    Kill,
}

/// Processus suivi : signal d'arrêt, code de sortie observable.
#[derive(Clone)]
pub struct ManagedChild {
    signals: mpsc::UnboundedSender<Signal>,
    exit: watch::Receiver<Option<i32>>,
}

impl ManagedChild {
    /// Prend la main sur [child] (ses flux stdout/stderr doivent déjà avoir
    /// été extraits par l'appelant s'il les lit).
    pub fn spawn(mut child: Child) -> Self {
        let (signal_tx, mut signal_rx) = mpsc::unbounded_channel::<Signal>();
        let (exit_tx, exit_rx) = watch::channel(None);
        #[cfg(unix)]
        let pid = child.id();

        tokio::spawn(async move {
            loop {
                tokio::select! {
                    status = child.wait() => {
                        let code = match status {
                            Ok(status) => exit_code(status),
                            Err(_) => -1,
                        };
                        let _ = exit_tx.send(Some(code));
                        break;
                    }
                    Some(signal) = signal_rx.recv() => {
                        match signal {
                            Signal::Term => {
                                #[cfg(unix)]
                                {
                                    if let Some(pid) = pid {
                                        // Le processus n'est pas encore récolté
                                        // (wait() n'a pas abouti) : le pid est sûr.
                                        unsafe { libc::kill(pid as libc::pid_t, libc::SIGTERM); }
                                    }
                                }
                                #[cfg(not(unix))]
                                {
                                    let _ = child.start_kill();
                                }
                            }
                            Signal::Kill => {
                                let _ = child.start_kill();
                            }
                        }
                    }
                }
            }
        });

        Self {
            signals: signal_tx,
            exit: exit_rx,
        }
    }

    /// Arrêt propre (SIGTERM). Sans effet si le processus est déjà terminé.
    pub fn terminate(&self) {
        let _ = self.signals.send(Signal::Term);
    }

    /// Arrêt forcé (SIGKILL).
    pub fn kill(&self) {
        let _ = self.signals.send(Signal::Kill);
    }

    /// Code de sortie, ou `None` si le processus tourne encore.
    pub fn exit_code(&self) -> Option<i32> {
        *self.exit.borrow()
    }

    pub fn has_exited(&self) -> bool {
        self.exit_code().is_some()
    }

    /// Attend la fin du processus et renvoie son code de sortie.
    pub async fn wait(&self) -> i32 {
        let mut rx = self.exit.clone();
        loop {
            if let Some(code) = *rx.borrow_and_update() {
                return code;
            }
            if rx.changed().await.is_err() {
                return rx.borrow().unwrap_or(-1);
            }
        }
    }
}

/// Code de sortie à la manière de Dart : négatif (−signal) pour un
/// processus tué par un signal.
fn exit_code(status: std::process::ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        return code;
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(signal) = status.signal() {
            return -signal;
        }
    }
    -1
}
