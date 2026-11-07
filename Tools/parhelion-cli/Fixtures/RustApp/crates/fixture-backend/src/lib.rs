//! A small stand-in for Rustle's Rust core: a backend that lists tracks.
//! Swift reaches it through bindings that UniFFI generates.

use std::sync::Arc;

uniffi::setup_scaffolding!();

#[derive(uniffi::Record)]
pub struct Track {
    pub id: u32,
    pub title: String,
    pub artist: String,
    pub seconds: u32,
}

#[derive(uniffi::Object)]
pub struct FixtureBackend {
    greeting: String,
}

#[uniffi::export]
impl FixtureBackend {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            greeting: "Hello from Rust".to_string(),
        })
    }

    pub fn greeting(&self) -> String {
        self.greeting.clone()
    }

    pub fn tracks(&self) -> Vec<Track> {
        vec![
            Track { id: 1, title: "Parhelion".into(), artist: "Sundog".into(), seconds: 215 },
            Track { id: 2, title: "Halo".into(), artist: "Sundog".into(), seconds: 187 },
            Track { id: 3, title: "Circumzenithal".into(), artist: "Ice Crystals".into(), seconds: 242 },
        ]
    }
}
