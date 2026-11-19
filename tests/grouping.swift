// run: tests/run-grouping.sh
import Foundation

func g(_ name: String, auto: Bool = false) -> Group { Group(id: UUID(), name: name, color: 0, auto: auto ? true : nil) }
let projects = ["acme", "placard", "orbit", "Harbor"]
var fails = 0
func check(_ title: String, cwd: String? = nil, _ groups: [Group], _ want: String, shorten: Bool = false) {
    let got = TerminalScript.autoName(title: title, cwd: cwd, groups: groups, projects: projects)
    let ok = (got?.name ?? "nil") == want && (got?.shorten != nil) == shorten
    if !ok { fails += 1 }
    print(ok ? "ok  " : "FAIL", title, "->", got?.name ?? "nil", got?.shorten != nil ? "(shorten)" : "")
}
let home = NSHomeDirectory()
// Terminal.app titles: folder, task, process, size
check("karimbaba \u{2014} \u{2733} Acme checkout bug \u{2014} claude \u{2014} 120\u{00D7}40", [g("Acme")], "Acme")
check("karimbaba \u{2014} \u{2733} Fix the acme checkout \u{2014} claude", [], "Acme")
check("karimbaba \u{2014} \u{2733} Fix the acme checkout \u{2014} claude", [g("Acme")], "Acme")
check("karimbaba \u{2014} \u{2733} Riley Moss call notes \u{2014} claude", [g("Riley")], "Riley")
check("karimbaba \u{2014} \u{2733} Placard flashing fix \u{2014} claude", [g("Placard Background", auto: true)], "Placard Background", shorten: true)
check("karimbaba \u{2014} \u{2733} Flash timing in Placard \u{2014} claude", [g("Placard Background", auto: true)], "Placard Background", shorten: true)
check("karimbaba \u{2014} \u{2733} Placard flashing fix \u{2014} claude", [g("Placard Background")], "Placard")
check("karimbaba \u{2014} \u{2733} Shortlist vendors \u{2014} claude", [g("Shortlist", auto: true)], "Shortlist")
check("karimbaba \u{2014} \u{2733} Deploy approval flow \u{2014} claude", [], "Deploy Approval")
check("karimbaba \u{2014} \u{2733} Deploy approval retry \u{2014} claude", [g("Deploy Approval", auto: true)], "Deploy Approval")
check("karimbaba \u{2014} \u{2733} Launch thread \u{2014} claude", [g("Launch Motion", auto: true)], "Launch Motion", shorten: true)
// Ghostty / iTerm2 titles: the program's title alone
check("\u{2733} Checkout bug", cwd: home + "/Developer/acme", [], "Acme")
check("\u{2733} Checkout bug", cwd: home + "/Developer/acme", [g("Acme")], "Acme")
check("\u{2827} Checkout bug", cwd: home + "/Developer/acme-admin", [g("Acme")], "Acme")
check("\u{2733} Fix the acme checkout", cwd: home, [], "Acme")
check("\u{2733} Make the hero less dead", cwd: home, [], "Hero Less")
check("Claude Code", cwd: home, [], "nil")
print(fails == 0 ? "all passed" : "\(fails) failed")
exit(fails == 0 ? 0 : 1)
