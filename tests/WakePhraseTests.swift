import Foundation

// MARK: - WakePhrase tests (pure functions, no concurrency)

@main
enum WakePhraseTests {

    static var failures = 0

    static func main() {
        // MARK: split — should match

        // Basic wake phrases (no command)
        checkMatch("ok jarvis",              WakePhrase.split("ok jarvis"),              cmd: "")
        checkMatch("OK JARVIS",              WakePhrase.split("OK JARVIS"),              cmd: "")
        checkMatch("okay jarvis",            WakePhrase.split("okay jarvis"),            cmd: "")
        checkMatch("ok kuku",                WakePhrase.split("ok kuku"),                cmd: "")
        checkMatch("ok cou cou",             WakePhrase.split("ok cou cou"),             cmd: "")
        checkMatch("hey jarvis",             WakePhrase.split("hey jarvis"),             cmd: "")
        checkMatch("Hey Jarvis",             WakePhrase.split("Hey Jarvis"),             cmd: "")

        // Command extracted from original text (casing/punctuation preserved)
        checkMatch("Okay, Jarvis, ajoute GitHub",
                   WakePhrase.split("Okay, Jarvis, ajoute GitHub"),             cmd: "ajoute GitHub")
        checkMatch("ok cuckoo add github",
                   WakePhrase.split("ok cuckoo add github"),                    cmd: "add github")
        checkMatch("ok jarvis ouvre figma",
                   WakePhrase.split("ok jarvis ouvre figma"),                   cmd: "ouvre figma")

        // Apostrophes, hyphens and accents preserved in command
        checkMatch("OK Jarvis, mets l'album de Daft Punk",
                   WakePhrase.split("OK Jarvis, mets l'album de Daft Punk"),   cmd: "mets l'album de Daft Punk")
        checkMatch("ok jarvis qu'est-ce que fait Claude ?",
                   WakePhrase.split("ok jarvis qu'est-ce que fait Claude ?"),  cmd: "qu'est-ce que fait Claude ?")

        // Wake anywhere in transcript (word-boundary search)
        checkMatch("euh ok jarvis mets de la musique",
                   WakePhrase.split("euh ok jarvis mets de la musique"),        cmd: "mets de la musique")
        checkMatch("la chanson dit ok jarvis",
                   WakePhrase.split("la chanson dit ok jarvis"),                cmd: "") // accepted false positive

        // LAST occurrence wins
        checkMatch("ok jarvis search ok jarvis play music",
                   WakePhrase.split("ok jarvis search ok jarvis play music"),   cmd: "play music")

        // Partial word-by-word delivery
        checkNoMatch("ok alone",             WakePhrase.split("ok"))
        checkMatch("ok jarvis partial",      WakePhrase.split("ok jarvis"),              cmd: "")
        checkMatch("ok jarvis with more",    WakePhrase.split("ok jarvis mets"),         cmd: "mets")

        // MARK: split — should NOT match
        checkNoMatch("standalone jarvis",    WakePhrase.split("jarvis"))
        checkNoMatch("standalone JARVIS",    WakePhrase.split("JARVIS"))
        checkNoMatch("partial jarvis ça va", WakePhrase.split("jarvis ça va"))
        checkNoMatch("jarvis comment",       WakePhrase.split("jarvis comment tu vas"))
        checkNoMatch("ok google",            WakePhrase.split("ok google"))
        checkNoMatch("hey siri",             WakePhrase.split("hey siri"))
        checkNoMatch("okkkk jarvis",         WakePhrase.split("okkkk jarvis"))
        checkNoMatch("empty",                WakePhrase.split(""))

        // Summary
        if failures == 0 { print("\n\(total)/\(total) tests passed.") }
        else { print("\n\(failures) test(s) FAILED."); exit(1) }
    }

    static var total = 0

    static func checkMatch(_ label: String, _ r: WakePhrase.SplitResult, cmd: String) {
        total += 1
        if !r.matched {
            print("✗  \(label) — expected match, got no match"); failures += 1; return
        }
        if r.command != cmd {
            print("✗  \(label) — matched ✓ but command \"\(r.command)\" ≠ \"\(cmd)\""); failures += 1; return
        }
        print("✓  \(label)")
    }

    static func checkNoMatch(_ label: String, _ r: WakePhrase.SplitResult) {
        total += 1
        if r.matched { print("✗  \(label) — expected no match, got matched (cmd: \"\(r.command)\")"); failures += 1 }
        else         { print("✓  \(label)") }
    }
}
