import SwiftUI

/// Content source for lecture videos — universities, educational channels, and dev creators.
///
/// Static enum (not @Model) because the source list ships with the app binary.
/// The `rawValue` string is stored as `sourceId` on Lecture and Course records.
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

    // More CS/ML/Research
    case statquest = "statquest"
    case benEater = "ben_eater"
    case reducible = "reducible"
    case sebastianLague = "sebastian_lague"
    case traversyMedia = "traversy_media"
    case liveOverflow = "live_overflow"
    case lexFridman = "lex_fridman"
    case deepMind = "deepmind"
    case yannicKilcher = "yannic_kilcher"

    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .mit: return "MIT OpenCourseWare"
        case .stanford: return "Stanford University"
        case .harvard: return "Harvard University"
        case .yale: return "Yale University"
        case .caltech: return "Caltech"
        case .berkeley: return "UC Berkeley"
        case .cmu: return "Carnegie Mellon"
        case .princeton: return "Princeton University"
        case .cornell: return "Cornell University"
        case .threeBlue1Brown: return "3Blue1Brown"
        case .khanAcademy: return "Khan Academy"
        case .crashCourse: return "CrashCourse"
        case .freeCodeCamp: return "freeCodeCamp"
        case .computerphile: return "Computerphile"
        case .numberphile: return "Numberphile"
        case .codingTrain: return "The Coding Train"
        case .fireship: return "Fireship"
        case .sentdex: return "sentdex"
        case .twoMinutePapers: return "Two Minute Papers"
        case .fastAI: return "fast.ai"
        case .andrejKarpathy: return "Andrej Karpathy"
        case .georgeHotz: return "george hotz"
        case .nvidiadev: return "NVIDIA Developer"
        case .janeStreet: return "Jane Street"
        case .primeagen: return "ThePrimeagen"
        case .noBoilerplate: return "No Boilerplate"
        case .jonGjengset: return "Jon Gjengset"
        case .tsoding: return "Tsoding"
        case .systemCrafters: return "System Crafters"
        case .tjDevries: return "TJ DeVries"
        case .statquest: return "StatQuest"
        case .benEater: return "Ben Eater"
        case .reducible: return "Reducible"
        case .sebastianLague: return "Sebastian Lague"
        case .traversyMedia: return "Traversy Media"
        case .liveOverflow: return "LiveOverflow"
        case .lexFridman: return "Lex Fridman"
        case .deepMind: return "Google DeepMind"
        case .yannicKilcher: return "Yannic Kilcher"
        }
    }

    var shortName: String {
        switch self {
        case .mit: return "MIT"
        case .stanford: return "Stanford"
        case .harvard: return "Harvard"
        case .yale: return "Yale"
        case .caltech: return "Caltech"
        case .berkeley: return "Berkeley"
        case .cmu: return "CMU"
        case .princeton: return "Princeton"
        case .cornell: return "Cornell"
        case .threeBlue1Brown: return "3B1B"
        case .khanAcademy: return "Khan"
        case .crashCourse: return "Crash Course"
        case .freeCodeCamp: return "freeCodeCamp"
        case .computerphile: return "Computerphile"
        case .numberphile: return "Numberphile"
        case .codingTrain: return "Coding Train"
        case .fireship: return "Fireship"
        case .sentdex: return "sentdex"
        case .twoMinutePapers: return "2min Papers"
        case .fastAI: return "fast.ai"
        case .andrejKarpathy: return "Karpathy"
        case .georgeHotz: return "geohot"
        case .nvidiadev: return "NVIDIA"
        case .janeStreet: return "Jane Street"
        case .primeagen: return "Prime"
        case .noBoilerplate: return "No Boilerplate"
        case .jonGjengset: return "Jon Gjengset"
        case .tsoding: return "Tsoding"
        case .systemCrafters: return "Sys Crafters"
        case .tjDevries: return "TJ"
        case .statquest: return "StatQuest"
        case .benEater: return "Ben Eater"
        case .reducible: return "Reducible"
        case .sebastianLague: return "Seb Lague"
        case .traversyMedia: return "Traversy"
        case .liveOverflow: return "LiveOverflow"
        case .lexFridman: return "Lex"
        case .deepMind: return "DeepMind"
        case .yannicKilcher: return "Yannic"
        }
    }

    var systemImage: String {
        switch self {
        case .mit: return "building.columns"
        case .stanford: return "graduationcap"
        case .harvard: return "book.closed"
        case .yale: return "theatermasks"
        case .caltech: return "atom"
        case .berkeley: return "leaf"
        case .cmu: return "cpu"
        case .princeton: return "building.2"
        case .cornell: return "mountain.2"
        case .threeBlue1Brown: return "function"
        case .khanAcademy: return "lightbulb"
        case .crashCourse: return "bolt.fill"
        case .freeCodeCamp: return "chevron.left.forwardslash.chevron.right"
        case .computerphile: return "desktopcomputer"
        case .numberphile: return "number"
        case .codingTrain: return "train.side.front.car"
        case .fireship: return "flame"
        case .sentdex: return "chart.line.uptrend.xyaxis"
        case .twoMinutePapers: return "doc.text.magnifyingglass"
        case .fastAI: return "brain"
        case .andrejKarpathy: return "brain.head.profile"
        case .georgeHotz: return "terminal"
        case .nvidiadev: return "square.stack.3d.up"
        case .janeStreet: return "chart.bar"
        case .primeagen: return "keyboard"
        case .noBoilerplate: return "gearshape.2"
        case .jonGjengset: return "wrench.and.screwdriver"
        case .tsoding: return "hammer"
        case .systemCrafters: return "text.and.command.macwindow"
        case .tjDevries: return "rectangle.and.pencil.and.ellipsis"
        case .statquest: return "chart.bar.xaxis"
        case .benEater: return "memorychip"
        case .reducible: return "arrow.triangle.branch"
        case .sebastianLague: return "gamecontroller"
        case .traversyMedia: return "globe"
        case .liveOverflow: return "lock.shield"
        case .lexFridman: return "mic"
        case .deepMind: return "brain"
        case .yannicKilcher: return "doc.text.magnifyingglass"
        }
    }

    // MARK: - Branding

    var brandColor: Color {
        switch self {
        case .mit: return Color(hex: 0xA31F34)
        case .stanford: return Color(hex: 0x8C1515)
        case .harvard: return Color(hex: 0xA41034)
        case .yale: return Color(hex: 0x00356B)
        case .caltech: return Color(hex: 0xFF6C0C)
        case .berkeley: return Color(hex: 0x003262)
        case .cmu: return Color(hex: 0xC41230)
        case .princeton: return Color(hex: 0xE77500)
        case .cornell: return Color(hex: 0xB31B1B)
        case .threeBlue1Brown: return Color(hex: 0x2B7CB3)
        case .khanAcademy: return Color(hex: 0x14BF96)
        case .crashCourse: return Color(hex: 0x2ECC71)
        case .freeCodeCamp: return Color(hex: 0x0A0A23)
        case .computerphile: return Color(hex: 0x1A8FE3)
        case .numberphile: return Color(hex: 0x8B4513)
        case .codingTrain: return Color(hex: 0xE91E63)
        case .fireship: return Color(hex: 0xF5820D)
        case .sentdex: return Color(hex: 0x4A90D9)
        case .twoMinutePapers: return Color(hex: 0x6C3483)
        case .fastAI: return Color(hex: 0x2980B9)
        case .andrejKarpathy: return Color(hex: 0x34495E)
        case .georgeHotz: return Color(hex: 0x1ABC9C)
        case .nvidiadev: return Color(hex: 0x76B900)
        case .janeStreet: return Color(hex: 0x0D3B66)
        case .primeagen: return Color(hex: 0xE74C3C)
        case .noBoilerplate: return Color(hex: 0xB7410E)
        case .jonGjengset: return Color(hex: 0xDEA584)
        case .tsoding: return Color(hex: 0x5B2C6F)
        case .systemCrafters: return Color(hex: 0x7D3C98)
        case .tjDevries: return Color(hex: 0x2C3E50)
        case .statquest: return Color(hex: 0x27AE60)
        case .benEater: return Color(hex: 0xE67E22)
        case .reducible: return Color(hex: 0x3498DB)
        case .sebastianLague: return Color(hex: 0x1ABC9C)
        case .traversyMedia: return Color(hex: 0x9B59B6)
        case .liveOverflow: return Color(hex: 0xE74C3C)
        case .lexFridman: return Color(hex: 0x2C3E50)
        case .deepMind: return Color(hex: 0x4285F4)
        case .yannicKilcher: return Color(hex: 0xF39C12)
        }
    }

    var gradientEndColor: Color {
        switch self {
        case .mit: return Color(hex: 0xD4525E)
        case .stanford: return Color(hex: 0xB84545)
        case .harvard: return Color(hex: 0xD44060)
        case .yale: return Color(hex: 0x3A6E9E)
        case .caltech: return Color(hex: 0xFFA05C)
        case .berkeley: return Color(hex: 0x3A6E95)
        case .cmu: return Color(hex: 0xE44560)
        case .princeton: return Color(hex: 0xFFA540)
        case .cornell: return Color(hex: 0xD44545)
        case .threeBlue1Brown: return Color(hex: 0x5BACCF)
        case .khanAcademy: return Color(hex: 0x4EDBB8)
        case .crashCourse: return Color(hex: 0x5DECA0)
        case .freeCodeCamp: return Color(hex: 0x3A3A5C)
        case .computerphile: return Color(hex: 0x5CB8F0)
        case .numberphile: return Color(hex: 0xC4753A)
        case .codingTrain: return Color(hex: 0xF06292)
        case .fireship: return Color(hex: 0xFFA94D)
        case .sentdex: return Color(hex: 0x7BB3E5)
        case .twoMinutePapers: return Color(hex: 0x9B59B6)
        case .fastAI: return Color(hex: 0x5DADE2)
        case .andrejKarpathy: return Color(hex: 0x5D6D7E)
        case .georgeHotz: return Color(hex: 0x48C9B0)
        case .nvidiadev: return Color(hex: 0xA3D940)
        case .janeStreet: return Color(hex: 0x1A6B99)
        case .primeagen: return Color(hex: 0xF07070)
        case .noBoilerplate: return Color(hex: 0xE76F51)
        case .jonGjengset: return Color(hex: 0xF0C8A8)
        case .tsoding: return Color(hex: 0x8E44AD)
        case .systemCrafters: return Color(hex: 0xAF7AC5)
        case .tjDevries: return Color(hex: 0x5D6D7E)
        case .statquest: return Color(hex: 0x52D98A)
        case .benEater: return Color(hex: 0xF0A654)
        case .reducible: return Color(hex: 0x6BB8E8)
        case .sebastianLague: return Color(hex: 0x48D1CC)
        case .traversyMedia: return Color(hex: 0xBB8FCE)
        case .liveOverflow: return Color(hex: 0xF07070)
        case .lexFridman: return Color(hex: 0x5D6D7E)
        case .deepMind: return Color(hex: 0x7BAAF7)
        case .yannicKilcher: return Color(hex: 0xF7C948)
        }
    }

    // MARK: - YouTube Integration

    var youtubeChannelId: String {
        switch self {
        case .mit: return "UCEBb1b_L6zDS3xTUrIALZOw"
        case .stanford: return "UCBa5G_ESCn8Uf67UGNEbXvA"
        case .harvard: return "UCT75CAoariMJGYEM-NTox9A"
        case .yale: return "UC4EY_qnSeAP1xGsh61eOoJA"
        case .caltech: return "UClGTZDyz3CSl92TgDqIr0nw"
        case .berkeley: return "UCZAXKyvvIV4uU4YvP5dmrmA"
        case .cmu: return "UCOWzl3JZ3q8CkNdNgumEcXw"
        case .princeton: return "UCcBYSgQTxc126-lj_gdrO8Q"
        case .cornell: return "UC7p_I0qxYZP94vhesuLAWNA"
        case .threeBlue1Brown: return "UCYO_jab_esuFRV4b17AJtAw"
        case .khanAcademy: return "UC4a-Gbdw7vOaccHmFo40b9g"
        case .crashCourse: return "UCX6b17PVsYBQ0ip5gyeme-Q"
        case .freeCodeCamp: return "UC8butISFwT-Wl7EV0hUK0BQ"
        case .computerphile: return "UC9-y-6csu5WGm29I7JiwpnA"
        case .numberphile: return "UCoxcjq-8xIDTYp3uz647V5A"
        case .codingTrain: return "UCvjgXvBlbQiydffZU7m1_aw"
        case .fireship: return "UCsBjURrPoezykLs9EqgamOA"
        case .sentdex: return "UCfzlCWGWYyIQ0aLC5w48gBQ"
        case .twoMinutePapers: return "UCbfYPyITQ-7l4upoX8nvctg"
        case .fastAI: return "UCX7Y2qWriXpqocG97SFW2OQ"
        case .andrejKarpathy: return "UCXUPKJO5MZQN11PqgIvyuvQ"
        case .georgeHotz: return "UCwgKmJM4ZJQRJ-U5NjvR2dg"
        case .nvidiadev: return "UCBHcMCGaiJhv-ESTcWGJPcw"
        case .janeStreet: return "UCDsVC_ewpcEW_AQcO-H-RDQ"
        case .primeagen: return "UC8ENHE5xdFSwx71u3fDH5Xw"
        case .noBoilerplate: return "UCUMwY9iS8oMyWDYIe6_RmoA"
        case .jonGjengset: return "UC_iD0xppBwwsrM9DegC5cQQ"
        case .tsoding: return "UCrqM0Ym_NbK1fqeQG2VIohg"
        case .systemCrafters: return "UCAiiOTio8Yu69c3XnR7nQBQ"
        case .tjDevries: return "UCd3dNckv1Za2coSaHGHl5aA"
        case .statquest: return "UCtYLUTtgS3k1Fg4y5tAhLbw"
        case .benEater: return "UCS0N5baNlQWJCUrhCEo8WlA"
        case .reducible: return "UCK8XIGR5kRidIw2fWqwyHRA"
        case .sebastianLague: return "UCmtyQOKKmrMVaKuRXz02jbQ"
        case .traversyMedia: return "UC29ju8bIPH5as8OGnQzwJyA"
        case .liveOverflow: return "UClcE-kVhqyiHCcjYwcpfj9w"
        case .lexFridman: return "UCSHZKyawb77ixDdsGog4iWA"
        case .deepMind: return "UCP7jMXSY2xbc3KCAE0MHQ-A"
        case .yannicKilcher: return "UCZHmQk67mSJgfCCTn7xBfew"
        }
    }

    enum ContentType { case ocwSitemap, youtubeAPI }

    var contentType: ContentType {
        switch self {
        case .mit: return .ocwSitemap
        default: return .youtubeAPI
        }
    }

    var isUniversity: Bool {
        switch self {
        case .mit, .stanford, .harvard, .yale, .caltech, .berkeley, .cmu, .princeton, .cornell:
            return true
        default:
            return false
        }
    }
}
