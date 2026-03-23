import SwiftUI

/// Content source for lecture videos — universities, educational channels, and dev creators.
///
/// Data-driven: each source's metadata is defined in a single `SourceMeta` entry.
/// Adding a new source = one line in the `catalog` dictionary + one enum case.
enum UniversitySource: String, CaseIterable, Identifiable, Codable {
    // Universities
    case mit = "mit"
    case stanford = "stanford"
    case harvard = "harvard"
    case yale = "yale"
    case caltech = "caltech"
    case berkeley = "berkeley"
    case cmu = "cmu"
    case princeton = "princeton"
    case cornell = "cornell"

    // Educational platforms
    case threeBlue1Brown = "3blue1brown"
    case khanAcademy = "khan_academy"
    case crashCourse = "crash_course"
    case freeCodeCamp = "freecodecamp"

    // CS/AI/ML creators
    case computerphile = "computerphile"
    case numberphile = "numberphile"
    case codingTrain = "coding_train"
    case fireship = "fireship"
    case sentdex = "sentdex"
    case twoMinutePapers = "two_minute_papers"
    case fastAI = "fast_ai"
    case andrejKarpathy = "andrej_karpathy"
    case georgeHotz = "george_hotz"
    case nvidiadev = "nvidia_dev"

    // Quant / Finance
    case janeStreet = "jane_street"

    // Dev tooling creators
    case primeagen = "primeagen"
    case noBoilerplate = "no_boilerplate"
    case jonGjengset = "jon_gjengset"
    case tsoding = "tsoding"
    case systemCrafters = "system_crafters"
    case tjDevries = "tj_devries"

    // Research / ML
    case statquest = "statquest"
    case benEater = "ben_eater"
    case reducible = "reducible"
    case sebastianLague = "sebastian_lague"
    case traversyMedia = "traversy_media"
    case liveOverflow = "live_overflow"
    case lexFridman = "lex_fridman"
    case deepMind = "deepmind"
    case yannicKilcher = "yannic_kilcher"

    // Creative / Production
    case matlab = "matlab"
    case blenderGuru = "blender_guru"
    case unrealEngine = "unreal_engine"
    case adamNeely = "adam_neely"
    case inTheMix = "in_the_mix"
    case musicTechHelp = "music_tech_help"
    case filmRiot = "film_riot"
    case meetTheGaffer = "meet_the_gaffer"

    var id: String { rawValue }

    // MARK: - Data-Driven Metadata

    private struct Meta {
        let display: String
        let short: String
        let icon: String
        let brand: UInt
        let gradient: UInt
        let channel: String
        let university: Bool
    }

    // One line per source — all metadata in one place.
    // To add a new source: add enum case + one entry here.
    private static let catalog: [UniversitySource: Meta] = [
        // Universities
        .mit:              Meta(display: "MIT OpenCourseWare",  short: "MIT",          icon: "building.columns",     brand: 0xA31F34, gradient: 0xD4525E, channel: "UCEBb1b_L6zDS3xTUrIALZOw", university: true),
        .stanford:         Meta(display: "Stanford University", short: "Stanford",     icon: "graduationcap",        brand: 0x8C1515, gradient: 0xB84545, channel: "UCBa5G_ESCn8Uf67UGNEbXvA", university: true),
        .harvard:          Meta(display: "Harvard University",  short: "Harvard",      icon: "book.closed",          brand: 0xA41034, gradient: 0xD44060, channel: "UCT75CAoariMJGYEM-NTox9A", university: true),
        .yale:             Meta(display: "Yale University",     short: "Yale",         icon: "theatermasks",         brand: 0x00356B, gradient: 0x3A6E9E, channel: "UC4EY_qnSeAP1xGsh61eOoJA", university: true),
        .caltech:          Meta(display: "Caltech",             short: "Caltech",      icon: "atom",                 brand: 0xFF6C0C, gradient: 0xFFA05C, channel: "UClGTZDyz3CSl92TgDqIr0nw", university: true),
        .berkeley:         Meta(display: "UC Berkeley",         short: "Berkeley",     icon: "leaf",                 brand: 0x003262, gradient: 0x3A6E95, channel: "UCZAXKyvvIV4uU4YvP5dmrmA", university: true),
        .cmu:              Meta(display: "Carnegie Mellon",     short: "CMU",          icon: "cpu",                  brand: 0xC41230, gradient: 0xE44560, channel: "UCOWzl3JZ3q8CkNdNgumEcXw", university: true),
        .princeton:        Meta(display: "Princeton University",short: "Princeton",    icon: "building.2",           brand: 0xE77500, gradient: 0xFFA540, channel: "UCcBYSgQTxc126-lj_gdrO8Q", university: true),
        .cornell:          Meta(display: "Cornell University",  short: "Cornell",      icon: "mountain.2",           brand: 0xB31B1B, gradient: 0xD44545, channel: "UC7p_I0qxYZP94vhesuLAWNA", university: true),
        // Educational platforms
        .threeBlue1Brown:  Meta(display: "3Blue1Brown",         short: "3B1B",         icon: "function",             brand: 0x2B7CB3, gradient: 0x5BACCF, channel: "UCYO_jab_esuFRV4b17AJtAw", university: false),
        .khanAcademy:      Meta(display: "Khan Academy",        short: "Khan",         icon: "lightbulb",            brand: 0x14BF96, gradient: 0x4EDBB8, channel: "UC4a-Gbdw7vOaccHmFo40b9g", university: false),
        .crashCourse:      Meta(display: "CrashCourse",         short: "Crash Course", icon: "bolt.fill",            brand: 0x2ECC71, gradient: 0x5DECA0, channel: "UCX6b17PVsYBQ0ip5gyeme-Q", university: false),
        .freeCodeCamp:     Meta(display: "freeCodeCamp",        short: "freeCodeCamp", icon: "chevron.left.forwardslash.chevron.right", brand: 0x0A0A23, gradient: 0x3A3A5C, channel: "UC8butISFwT-Wl7EV0hUK0BQ", university: false),
        // CS/AI/ML creators
        .computerphile:    Meta(display: "Computerphile",       short: "Computerphile",icon: "desktopcomputer",      brand: 0x1A8FE3, gradient: 0x5CB8F0, channel: "UC9-y-6csu5WGm29I7JiwpnA", university: false),
        .numberphile:      Meta(display: "Numberphile",         short: "Numberphile",  icon: "number",               brand: 0x8B4513, gradient: 0xC4753A, channel: "UCoxcjq-8xIDTYp3uz647V5A", university: false),
        .codingTrain:      Meta(display: "The Coding Train",    short: "Coding Train", icon: "train.side.front.car", brand: 0xE91E63, gradient: 0xF06292, channel: "UCvjgXvBlbQiydffZU7m1_aw", university: false),
        .fireship:         Meta(display: "Fireship",            short: "Fireship",     icon: "flame",                brand: 0xF5820D, gradient: 0xFFA94D, channel: "UCsBjURrPoezykLs9EqgamOA", university: false),
        .sentdex:          Meta(display: "sentdex",             short: "sentdex",      icon: "chart.line.uptrend.xyaxis", brand: 0x4A90D9, gradient: 0x7BB3E5, channel: "UCfzlCWGWYyIQ0aLC5w48gBQ", university: false),
        .twoMinutePapers:  Meta(display: "Two Minute Papers",   short: "2min Papers",  icon: "doc.text.magnifyingglass", brand: 0x6C3483, gradient: 0x9B59B6, channel: "UCbfYPyITQ-7l4upoX8nvctg", university: false),
        .fastAI:           Meta(display: "fast.ai",             short: "fast.ai",      icon: "brain",                brand: 0x2980B9, gradient: 0x5DADE2, channel: "UCX7Y2qWriXpqocG97SFW2OQ", university: false),
        .andrejKarpathy:   Meta(display: "Andrej Karpathy",     short: "Karpathy",     icon: "brain.head.profile",   brand: 0x34495E, gradient: 0x5D6D7E, channel: "UCXUPKJO5MZQN11PqgIvyuvQ", university: false),
        .georgeHotz:       Meta(display: "george hotz",         short: "geohot",       icon: "terminal",             brand: 0x1ABC9C, gradient: 0x48C9B0, channel: "UCwgKmJM4ZJQRJ-U5NjvR2dg", university: false),
        .nvidiadev:        Meta(display: "NVIDIA Developer",    short: "NVIDIA",       icon: "square.stack.3d.up",   brand: 0x76B900, gradient: 0xA3D940, channel: "UCBHcMCGaiJhv-ESTcWGJPcw", university: false),
        // Quant
        .janeStreet:       Meta(display: "Jane Street",         short: "Jane Street",  icon: "chart.bar",            brand: 0x0D3B66, gradient: 0x1A6B99, channel: "UCDsVC_ewpcEW_AQcO-H-RDQ", university: false),
        // Dev tooling
        .primeagen:        Meta(display: "ThePrimeagen",        short: "Prime",        icon: "keyboard",             brand: 0xE74C3C, gradient: 0xF07070, channel: "UC8ENHE5xdFSwx71u3fDH5Xw", university: false),
        .noBoilerplate:    Meta(display: "No Boilerplate",      short: "No Boilerplate",icon: "gearshape.2",         brand: 0xB7410E, gradient: 0xE76F51, channel: "UCUMwY9iS8oMyWDYIe6_RmoA", university: false),
        .jonGjengset:      Meta(display: "Jon Gjengset",        short: "Jon Gjengset", icon: "wrench.and.screwdriver",brand: 0xDEA584, gradient: 0xF0C8A8, channel: "UC_iD0xppBwwsrM9DegC5cQQ", university: false),
        .tsoding:          Meta(display: "Tsoding",             short: "Tsoding",      icon: "hammer",               brand: 0x5B2C6F, gradient: 0x8E44AD, channel: "UCrqM0Ym_NbK1fqeQG2VIohg", university: false),
        .systemCrafters:   Meta(display: "System Crafters",     short: "Sys Crafters", icon: "text.and.command.macwindow", brand: 0x7D3C98, gradient: 0xAF7AC5, channel: "UCAiiOTio8Yu69c3XnR7nQBQ", university: false),
        .tjDevries:        Meta(display: "TJ DeVries",          short: "TJ",           icon: "rectangle.and.pencil.and.ellipsis", brand: 0x2C3E50, gradient: 0x5D6D7E, channel: "UCd3dNckv1Za2coSaHGHl5aA", university: false),
        // Research / ML
        .statquest:        Meta(display: "StatQuest",           short: "StatQuest",    icon: "chart.bar.xaxis",      brand: 0x27AE60, gradient: 0x52D98A, channel: "UCtYLUTtgS3k1Fg4y5tAhLbw", university: false),
        .benEater:         Meta(display: "Ben Eater",           short: "Ben Eater",    icon: "memorychip",           brand: 0xE67E22, gradient: 0xF0A654, channel: "UCS0N5baNlQWJCUrhCEo8WlA", university: false),
        .reducible:        Meta(display: "Reducible",           short: "Reducible",    icon: "arrow.triangle.branch",brand: 0x3498DB, gradient: 0x6BB8E8, channel: "UCK8XIGR5kRidIw2fWqwyHRA", university: false),
        .sebastianLague:   Meta(display: "Sebastian Lague",     short: "Seb Lague",    icon: "gamecontroller",       brand: 0x1ABC9C, gradient: 0x48D1CC, channel: "UCmtyQOKKmrMVaKuRXz02jbQ", university: false),
        .traversyMedia:    Meta(display: "Traversy Media",      short: "Traversy",     icon: "globe",                brand: 0x9B59B6, gradient: 0xBB8FCE, channel: "UC29ju8bIPH5as8OGnQzwJyA", university: false),
        .liveOverflow:     Meta(display: "LiveOverflow",        short: "LiveOverflow", icon: "lock.shield",          brand: 0xE74C3C, gradient: 0xF07070, channel: "UClcE-kVhqyiHCcjYwcpfj9w", university: false),
        .lexFridman:       Meta(display: "Lex Fridman",         short: "Lex",          icon: "mic",                  brand: 0x2C3E50, gradient: 0x5D6D7E, channel: "UCSHZKyawb77ixDdsGog4iWA", university: false),
        .deepMind:         Meta(display: "Google DeepMind",     short: "DeepMind",     icon: "brain",                brand: 0x4285F4, gradient: 0x7BAAF7, channel: "UCP7jMXSY2xbc3KCAE0MHQ-A", university: false),
        .yannicKilcher:    Meta(display: "Yannic Kilcher",      short: "Yannic",       icon: "doc.text.magnifyingglass", brand: 0xF39C12, gradient: 0xF7C948, channel: "UCZHmQk67mSJgfCCTn7xBfew", university: false),
        // Creative / Production
        .matlab:           Meta(display: "MATLAB",              short: "MATLAB",       icon: "x.squareroot",         brand: 0x0076A8, gradient: 0x40A8D8, channel: "UCgdHSFcXvkN6O3NXvif0-pA", university: false),
        .blenderGuru:      Meta(display: "Blender Guru",        short: "Blender",      icon: "cube",                 brand: 0xE87D0D, gradient: 0xF4A94D, channel: "UCOKHwx1VCdgnxwbjyb9Iu1g", university: false),
        .unrealEngine:     Meta(display: "Unreal Engine",       short: "Unreal",       icon: "paintbrush",           brand: 0x313131, gradient: 0x5A5A5A, channel: "UCBobmJyzsJ6Ll7UbfhI4iwQ", university: false),
        .adamNeely:        Meta(display: "Adam Neely",          short: "Adam Neely",   icon: "music.note",           brand: 0xC0392B, gradient: 0xE67373, channel: "UCnkp4xDOwqqJD7sSM3xdUiQ", university: false),
        .inTheMix:         Meta(display: "In The Mix",          short: "ITM",          icon: "slider.horizontal.3",  brand: 0x8E44AD, gradient: 0xBB8FCE, channel: "UCIcCXe3iWo6lq-iWKV40Oug", university: false),
        .musicTechHelp:    Meta(display: "MusicTechHelpGuy",    short: "MTH",          icon: "waveform",             brand: 0x2E86C1, gradient: 0x5DADE2, channel: "UC21BwBKSKiPFbNvzl3-eh_A", university: false),
        .filmRiot:         Meta(display: "Film Riot",           short: "Film Riot",    icon: "film",                 brand: 0xD35400, gradient: 0xF08040, channel: "UC6P24bhhCmMPOcujA9PKPTA", university: false),
        .meetTheGaffer:    Meta(display: "Meet The Gaffer",     short: "Gaffer",       icon: "lightbulb.max",        brand: 0xF1C40F, gradient: 0xF7DC6F, channel: "UCt7_XcAZ6vyc0j55qWDrjZQ", university: false),
    ]

    private var meta: Meta { Self.catalog[self]! }

    // MARK: - Public API (all O(1) dictionary lookups)

    var displayName: String { meta.display }
    var shortName: String { meta.short }
    var systemImage: String { meta.icon }
    var brandColor: Color { Color(hex: meta.brand) }
    var gradientEndColor: Color { Color(hex: meta.gradient) }
    var youtubeChannelId: String { meta.channel }
    var isUniversity: Bool { meta.university }

    var contentType: ContentType {
        self == .mit ? .ocwSitemap : .youtubeAPI
    }

    enum ContentType { case ocwSitemap, youtubeAPI }
}
