import Carbon

/// Global hotkeys through Carbon: no Accessibility permission needed.
@MainActor
final class Hotkeys {
    static let shared = Hotkeys()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    nonisolated static let ctrlOpt = UInt32(controlKey | optionKey)

    func register(key: Int, mods: UInt32 = ctrlOpt, _ handler: @escaping () -> Void) {
        installIfNeeded()
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x504C4344), id: id)   // 'PLCD'
        if RegisterEventHotKey(UInt32(key), mods, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        }
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { Hotkeys.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
