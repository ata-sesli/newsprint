import Foundation

public struct PresetSource: Identifiable, Hashable, Sendable {
    public var id: String { url.absoluteString }
    public let title: String
    public let url: URL
    public let category: String
    public let kind: SourceKind

    public init(title: String, url: URL, category: String, kind: SourceKind) {
        self.title = title
        self.url = url
        self.category = category
        self.kind = kind
    }
}

public enum PresetSourceCatalog {
    public static let all: [PresetSource] = [
        preset("Ahead of AI", "https://magazine.sebastianraschka.com/feed", "AI Research & Digests", .blog),
        preset("AlphaSignal", "https://alphasignalai.substack.com/feed", "AI Research & Digests", .blog),
        preset("Andrew Kelley", "https://andrewkelley.me/rss.xml", "Low-Level & Systems Engineering", .blog),
        preset("Carnegie Mellon ML Blog", "https://blog.ml.cmu.edu/feed/", "AI Research & Digests", .blog),
        preset("Cloudflare Blog", "https://blog.cloudflare.com/rss/", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Commonplace - Commoncog", "https://commoncog.com/blog/rss/", "Technical Essays & Engineering Judgment", .blog),
        preset("Communications of the ACM", "https://cacm.acm.org/feed/", "General CS & Research Journalism", .blog),
        preset("Crunchy Data Blog", "https://www.crunchydata.com/blog/rss.xml", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Dan Luu", "https://danluu.com/atom.xml", "Low-Level & Systems Engineering", .blog),
        preset("Daniel Lemire", "https://lemire.me/blog/feed/", "Low-Level & Systems Engineering", .blog),
        preset("Datadog Engineering", "https://www.datadoghq.com/blog/engineering/index.xml", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("DoorDash Engineering", "https://careersatdoordash.com/engineering-blog/feed/", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("DuckDB Engineering Blog", "https://duckdb.org/feed.xml", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Eli Bendersky", "https://eli.thegreenplace.net/feeds/all.atom.xml", "Low-Level & Systems Engineering", .blog),
        preset("Fabien Sanglard", "https://fabiensanglard.net/rss.xml", "Low-Level & Systems Engineering", .blog),
        preset("Fly.io Blog", "https://fly.io/blog/feed.xml", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("GitHub Engineering", "https://github.blog/category/engineering/feed/", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Google Research Blog", "https://research.google/blog/rss/", "AI Research & Digests", .blog),
        preset("Hugging Face Blog", "https://huggingface.co/blog/feed.xml", "AI Research & Digests", .blog),
        preset("Hugging Face Daily Papers - Unofficial RSS", "https://papers.takara.ai/api/feed", "AI Research & Digests", .blog),
        preset("Import AI", "https://jack-clark.net/feed/", "AI Research & Digests", .blog),
        preset("Interrupt - Memfault", "https://interrupt.memfault.com/blog/feed.xml", "Low-Level & Systems Engineering", .blog),
        preset("Irrational Exuberance - Will Larson", "https://lethain.com/feeds/", "Technical Essays & Engineering Judgment", .blog),
        preset("Jane Street Tech Blog", "https://blog.janestreet.com/feed.xml", "Programming Languages & Compilers", .blog),
        preset("Jay Alammar", "https://jalammar.github.io/feed.xml", "AI Research & Digests", .blog),
        preset("Julia Evans", "https://jvns.ca/atom.xml", "Technical Essays & Engineering Judgment", .blog),
        preset("Last Week in AI", "https://lastweekin.ai/feed", "AI Research & Digests", .blog),
        preset("Latent Space", "https://www.latent.space/feed", "AI Research & Digests", .blog),
        preset("Lil’Log - Lilian Weng", "https://lilianweng.github.io/index.xml", "AI Research & Digests", .blog),
        preset("LLVM Project Blog", "https://blog.llvm.org/index.xml", "Programming Languages & Compilers", .blog),
        preset("Martin Kleppmann", "https://feeds.feedburner.com/martinkl?format=xml", "Technical Essays & Engineering Judgment", .blog),
        preset("Meta Engineering", "https://engineering.fb.com/feed/", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Null Program", "https://nullprogram.com/feed/", "Low-Level & Systems Engineering", .blog),
        preset("NVIDIA Developer Blog", "https://developer.nvidia.com/blog/feed", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("PL Perspectives", "https://blog.sigplan.org/feed/", "Programming Languages & Compilers", .blog),
        preset("PlanetScale Blog", "https://planetscale.com/blog/feed.atom", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("PortSwigger Research", "https://portswigger.net/research/rss", "Security Research", .blog),
        preset("Postgres Weekly", "https://postgresweekly.com/rss/", "General CS & Research Journalism", .blog),
        preset("Project Zero", "https://projectzero.google/feed.xml", "Security Research", .blog),
        preset("Quanta Magazine", "https://api.quantamagazine.org/feed/", "General CS & Research Journalism", .blog),
        preset("Rust Blog", "https://blog.rust-lang.org/feed.xml", "Programming Languages & Compilers", .blog),
        preset("Signal Blog", "https://signal.org/blog/rss.xml", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Simon Willison", "https://simonwillison.net/atom/everything/", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Spotify Engineering", "https://engineering.atspotify.com/feed/", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Tailscale Blog", "https://tailscale.com/blog/index.xml", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("The Pragmatic Engineer", "https://blog.pragmaticengineer.com/rss/", "Technical Essays & Engineering Judgment", .blog),
        preset("This Week in Rust", "https://this-week-in-rust.org/rss.xml", "Programming Languages & Compilers", .blog),
        preset("TigerBeetle Blog", "https://tigerbeetle.com/blog/atom.xml", "Production Infrastructure, Databases & Builder Signal", .blog),
        preset("Trail of Bits Blog", "https://blog.trailofbits.com/feed/", "Security Research", .blog),
        preset("Web Browser Engineering", "https://browser.engineering/rss.xml", "Low-Level & Systems Engineering", .blog)
    ]

    public static func youtubeFeedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           url.host()?.localizedCaseInsensitiveContains("youtube.com") == true,
           url.path.contains("/feeds/videos.xml") {
            return url
        }

        var components = URLComponents(string: "https://www.youtube.com/feeds/videos.xml")
        components?.queryItems = [URLQueryItem(name: "channel_id", value: trimmed)]
        return components?.url
    }

    private static func preset(_ title: String, _ urlString: String, _ category: String, _ kind: SourceKind) -> PresetSource {
        PresetSource(title: title, url: URL(string: urlString)!, category: category, kind: kind)
    }
}
