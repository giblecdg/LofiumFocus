import SwiftUI
import AVFoundation
import Combine

@main
struct LofiumFocusApp: App {
    var body: some Scene {
        WindowGroup {
            TimerScreen()
        }
    }
}

// Themes
let pastelTheme = (bg: Color(red: 1, green: 0.96, blue: 0.97), card: Color(red: 1, green: 0.89, blue: 0.91), p: Color(red: 1, green: 0.71, blue: 0.78), s: Color(red: 0.78, green: 0.64, blue: 0.83), a: Color(red: 0.64, green: 0.83, blue: 0.68), t: Color(red: 0.35, green: 0.29, blue: 0.42))
let mintTheme = (bg: Color(red: 0.94, green: 0.98, blue: 0.96), card: Color(red: 0.83, green: 0.95, blue: 0.89), p: Color(red: 0.48, green: 0.79, blue: 0.64), s: Color(red: 0.58, green: 0.83, blue: 0.76), a: Color(red: 1, green: 0.83, blue: 0.64), t: Color(red: 0.18, green: 0.37, blue: 0.31))
let lavenderTheme = (bg: Color(red: 0.96, green: 0.95, blue: 1), card: Color(red: 0.91, green: 0.89, blue: 1), p: Color(red: 0.77, green: 0.71, blue: 0.99), s: Color(red: 0.65, green: 0.54, blue: 0.98), a: Color(red: 1, green: 0.77, blue: 0.88), t: Color(red: 0.3, green: 0.24, blue: 0.42))
let peachTheme = (bg: Color(red: 1, green: 0.97, blue: 0.94), card: Color(red: 1, green: 0.91, blue: 0.85), p: Color(red: 1, green: 0.72, blue: 0.58), s: Color(red: 1, green: 0.8, blue: 0.62), a: Color(red: 0.71, green: 0.83, blue: 1), t: Color(red: 0.42, green: 0.27, blue: 0.14))
let themes = [pastelTheme, mintTheme, lavenderTheme, peachTheme]
let themeNames = ["Pastel Dream", "Mint Lofi", "Lavender Chill", "Peachy Vibes"]

struct FocusSession: Codable, Identifiable {
    let id = UUID()
    let date = Date()
    let duration: Int
}

class VM: ObservableObject {
    @Published var time = 1500
    @Published var running = false
    @Published var sel = 25
    @Published var brk = false
    @Published var sessions = [FocusSession]()
    @Published var themeIdx = 0
    @Published var playing = false
    @Published var track = "Paused"
    @Published var showCustom = false
    @Published var custom = ""
    @Published var sessionCount = 0
    @Published var isLongBreak = false
    
    // Break Settings
    @Published var shortBreakDuration = 5
    @Published var longBreakDuration = 15
    @Published var sessionsUntilLongBreak = 4
    
    // Streak
    @Published var currentStreak = 0
    @Published var lastSessionDate: Date?
    
    // Ambient Sounds
    @Published var ambientPlaying = false
    @Published var selectedAmbient = "Silence"
    var ambientPlayer: AVPlayer?
    
    var timer: Timer?
    var player: AVPlayer?
    var obs: NSObjectProtocol?
    let playlist = (1...20).map { "lofi_\(String(format: "%02d", $0))" }
    var shuffled = [String]()
    var idx = 0
    
    init() {
        if let d = UserDefaults.standard.data(forKey: "s"), let s = try? JSONDecoder().decode([FocusSession].self, from: d) {
            sessions = s
        }
        
        // Load break settings
        shortBreakDuration = UserDefaults.standard.object(forKey: "shortBreak") as? Int ?? 5
        longBreakDuration = UserDefaults.standard.object(forKey: "longBreak") as? Int ?? 15
        sessionsUntilLongBreak = UserDefaults.standard.object(forKey: "sessionsLong") as? Int ?? 4
        sessionCount = UserDefaults.standard.integer(forKey: "sessionCount")
        
        // Load streak
        currentStreak = UserDefaults.standard.integer(forKey: "currentStreak")
        if let dateData = UserDefaults.standard.object(forKey: "lastSessionDate") as? Date {
            lastSessionDate = dateData
        }
        
        // Load ambient sound
        selectedAmbient = UserDefaults.standard.string(forKey: "selectedAmbient") ?? "Silence"
        
        checkStreak()
        
        shuffled = playlist.shuffled()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }
    
    func checkStreak() {
        guard let last = lastSessionDate else { return }
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(last) {
            return
        }
        
        if calendar.isDateInYesterday(last) {
            return
        }
        
        currentStreak = 0
        saveStreak()
    }
    
    func updateStreak() {
        let calendar = Calendar.current
        let now = Date()
        
        if let last = lastSessionDate {
            if calendar.isDateInToday(last) {
                return
            }
            
            if calendar.isDateInYesterday(last) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }
        
        lastSessionDate = now
        saveStreak()
    }
    
    func saveStreak() {
        UserDefaults.standard.set(currentStreak, forKey: "currentStreak")
        UserDefaults.standard.set(lastSessionDate, forKey: "lastSessionDate")
    }
    
    func start() {
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            if s.time > 0 { s.time -= 1 } else { s.done() }
        }
    }
    
    func pause() {
        running = false
        timer?.invalidate()
        if !brk && sel > 0 {
            let e = (sel * 60 - time) / 60
            if e > 0 {
                sessions.append(FocusSession(duration: e))
                save()
            }
        }
    }
    
    func reset() {
        running = false
        timer?.invalidate()
        time = sel * 60
        brk = false
        isLongBreak = false
    }
    
    func skipBreak() {
        guard brk else { return }
        timer?.invalidate()
        running = false
        brk = false
        isLongBreak = false
        time = sel * 60
    }
    
    func setTime(_ m: Int) {
        sel = m
        time = m * 60
        running = false
        brk = false
        isLongBreak = false
        timer?.invalidate()
    }
    
    func setCustom() {
        guard let m = Int(custom), m > 0, m <= 180 else { return }
        setTime(m)
        showCustom = false
        custom = ""
    }
    
    func done() {
        timer?.invalidate()
        running = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        if !brk {
            // Focus session completed
            sessions.append(FocusSession(duration: sel))
            save()
            updateStreak()
            
            sessionCount += 1
            UserDefaults.standard.set(sessionCount, forKey: "sessionCount")
            
            // Check if it's time for long break
            if sessionCount % sessionsUntilLongBreak == 0 {
                isLongBreak = true
                time = longBreakDuration * 60
            } else {
                isLongBreak = false
                time = shortBreakDuration * 60
            }
            
            brk = true
            start()
        } else {
            // Break completed
            brk = false
            isLongBreak = false
            time = sel * 60
        }
    }
    
    func toggle() { playing ? stop() : play() }
    
    func play() {
        guard idx < shuffled.count else {
            shuffled = playlist.shuffled()
            idx = 0
            play()
            return
        }
        let n = shuffled[idx]
        var u = Bundle.main.url(forResource: "Music/\(n)", withExtension: "mp3")
        if u == nil { u = Bundle.main.url(forResource: n, withExtension: "mp3") }
        guard let url = u else {
            idx += 1
            if idx < shuffled.count { play() }
            return
        }
        if let o = obs { NotificationCenter.default.removeObserver(o) }
        player = AVPlayer(url: url)
        obs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            self?.idx += 1
            self?.play()
        }
        player?.play()
        playing = true
        track = n.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    func stop() {
        player?.pause()
        if let o = obs { NotificationCenter.default.removeObserver(o); obs = nil }
        playing = false
        track = "Paused"
    }
    
    func skip() { idx += 1; play() }
    
    func today() -> (Int, Int) {
        let c = Calendar.current
        let t = c.startOfDay(for: Date())
        let s = sessions.filter { c.isDate($0.date, inSameDayAs: t) }
        return (s.count, s.reduce(0) { $0 + $1.duration })
    }
    
    func total() -> (Int, Int) {
        (sessions.count, sessions.reduce(0) { $0 + $1.duration })
    }
    
    func fmt() -> String { String(format: "%02d:%02d", time / 60, time % 60) }
    
    func save() {
        if let e = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(e, forKey: "s")
        }
    }
    
    func weeklyData() -> [(day: String, minutes: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [(String, Int)] = []
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        
        for i in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayName = formatter.string(from: date)
            let daySessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let totalMinutes = daySessions.reduce(0) { $0 + $1.duration }
            result.append((dayName, totalMinutes))
        }
        
        return result
    }
    
    func weeklyStats() -> (sessions: Int, minutes: Int, avgPerDay: Int, bestDay: String) {
        let weekData = weeklyData()
        let calendar = Calendar.current
        let now = Date()
        
        let totalSessions = sessions.filter { sess in
            calendar.isDate(sess.date, equalTo: now, toGranularity: .weekOfYear)
        }.count
        
        let totalMinutes = weekData.reduce(0) { $0 + $1.minutes }
        let avg = totalMinutes / 7
        let best = weekData.max(by: { $0.minutes < $1.minutes })
        
        return (totalSessions, totalMinutes, avg, best?.day ?? "N/A")
    }
    
    func saveBreakSettings() {
        UserDefaults.standard.set(shortBreakDuration, forKey: "shortBreak")
        UserDefaults.standard.set(longBreakDuration, forKey: "longBreak")
        UserDefaults.standard.set(sessionsUntilLongBreak, forKey: "sessionsLong")
    }
    
    // MARK: - Ambient Sounds
    func playAmbient(_ sound: String) {
        stopAmbient()
        selectedAmbient = sound
        UserDefaults.standard.set(sound, forKey: "selectedAmbient")
        
        guard sound != "Silence" else { return }
        
        let filename: String
        switch sound {
        case "Rain": filename = "rain"
        case "Fireplace": filename = "fireplace"
        case "White Noise": filename = "whitenoise"
        case "Cafe": filename = "cafe"
        default: return
        }
        
        var url = Bundle.main.url(forResource: "Ambient/\(filename)", withExtension: "mp3")
        if url == nil { url = Bundle.main.url(forResource: filename, withExtension: "mp3") }
        
        guard let soundUrl = url else { return }
        
        ambientPlayer = AVPlayer(url: soundUrl)
        ambientPlayer?.volume = 0
        ambientPlayer?.play()
        
        // Fade in
        for i in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { [weak self] in
                self?.ambientPlayer?.volume = Float(i) * 0.06
            }
        }
        
        // Loop
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: ambientPlayer?.currentItem, queue: .main) { [weak self] _ in
            self?.ambientPlayer?.seek(to: .zero)
            self?.ambientPlayer?.play()
        }
        
        ambientPlaying = true
    }
    
    func stopAmbient() {
        guard let player = ambientPlayer, ambientPlaying else {
            ambientPlaying = false
            return
        }
        
        // Fade out
        for i in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { [weak self] in
                self?.ambientPlayer?.volume = Float(10 - i) * 0.06
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            player.pause()
            self?.ambientPlayer = nil
            self?.ambientPlaying = false
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat = 12
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.7), color]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
    }
}

struct TimerScreen: View {
    @StateObject var vm = VM()
    @State var showSet = false
    @State var showStat = false
    @State var showAmbient = false
    
    var th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color) { themes[vm.themeIdx] }
    
    var progressColor: Color {
        if vm.brk {
            return vm.isLongBreak ? th.a : th.s
        }
        return th.p
    }
    
    var totalTime: Int {
        if vm.brk {
            return (vm.isLongBreak ? vm.longBreakDuration : vm.shortBreakDuration) * 60
        }
        return vm.sel * 60
    }
    
    var progress: Double {
        let total = Double(totalTime)
        let remaining = Double(vm.time)
        return max(0, min(1, (total - remaining) / total))
    }
    
    var body: some View {
        ZStack {
            th.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text("LofiumFocus").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(th.t)
                        Spacer()
                        Button { showStat = true } label: {
                            Image(systemName: "chart.bar.fill").font(.system(size: 20)).foregroundColor(th.t)
                                .frame(width: 44, height: 44).background(th.card).cornerRadius(12)
                        }
                        Button { showSet = true } label: {
                            Image(systemName: "gearshape.fill").font(.system(size: 20)).foregroundColor(th.t)
                                .frame(width: 44, height: 44).background(th.card).cornerRadius(12)
                        }
                    }.padding(.horizontal)
                    
                    NewCat(th: th, run: vm.running, streak: vm.currentStreak).frame(height: 180)
                    
                    if vm.currentStreak > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill").foregroundColor(vm.currentStreak >= 7 ? .orange : th.p)
                            Text("\(vm.currentStreak) day\(vm.currentStreak == 1 ? "" : "s") streak!").font(.system(size: 14, weight: .bold)).foregroundColor(th.t)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(th.card).cornerRadius(20)
                    }
                    
                    VStack(spacing: 20) {
                        if vm.brk {
                            Text(vm.isLongBreak ? "🎉 Long Break" : "☕ Break").font(.system(size: 14, weight: .bold)).foregroundColor(th.s).textCase(.uppercase)
                        } else {
                            HStack(spacing: 8) {
                                Text("🎯 Focus").font(.system(size: 14, weight: .bold)).foregroundColor(th.s).textCase(.uppercase)
                                Text("(\(vm.sessionCount % vm.sessionsUntilLongBreak)/\(vm.sessionsUntilLongBreak))").font(.system(size: 12, weight: .semibold)).foregroundColor(th.s.opacity(0.6))
                            }
                        }
                        
                        ZStack {
                            ProgressRing(progress: progress, color: progressColor)
                                .frame(width: 240, height: 240)
                            
                            Text(vm.fmt()).font(.system(size: 72, weight: .bold, design: .rounded)).foregroundColor(th.t).monospacedDigit()
                        }
                        
                        HStack(spacing: 12) {
                            Button { vm.running ? vm.pause() : vm.start() } label: {
                                HStack {
                                    Image(systemName: vm.running ? "pause.fill" : "play.fill")
                                    Text(vm.running ? "Pause" : "Start").fontWeight(.bold)
                                }.foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56).background(th.p).cornerRadius(16)
                            }
                            
                            if vm.brk {
                                Button { vm.skipBreak() } label: {
                                    HStack {
                                        Image(systemName: "forward.fill")
                                        Text("Skip").fontWeight(.bold)
                                    }.foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56).background(th.a).cornerRadius(16)
                                }
                            } else {
                                Button { vm.reset() } label: {
                                    Image(systemName: "arrow.counterclockwise").foregroundColor(.white)
                                        .frame(width: 56, height: 56).background(th.s).cornerRadius(16)
                                }
                            }
                        }
                        
                        if !vm.brk {
                            HStack(spacing: 10) {
                                ForEach([15, 25, 45, 60], id: \.self) { m in
                                    Button { vm.setTime(m) } label: {
                                        Text("\(m)").font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(vm.sel == m ? .white : th.t).frame(maxWidth: .infinity).padding(.vertical, 12)
                                            .background(vm.sel == m ? th.a : .white).cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(th.a, lineWidth: 2))
                                    }
                                }
                            }
                            Button { vm.showCustom = true } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Custom").font(.system(size: 15, weight: .semibold))
                                }.foregroundColor(th.t.opacity(0.7)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(th.a.opacity(0.2)).cornerRadius(12)
                            }
                        }
                    }.padding(28).background(th.card).cornerRadius(24).padding(.horizontal)
                    
                    HStack(spacing: 15) {
                        Image(systemName: "music.note").font(.system(size: 24)).foregroundColor(.white)
                            .frame(width: 50, height: 50).background(th.p).cornerRadius(12)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lofi Beats").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                            Text(vm.playing ? "🎵 \(vm.track)" : "⏸ \(vm.track)").font(.system(size: 12)).foregroundColor(th.s).lineLimit(1)
                        }
                        Spacer()
                        if vm.playing {
                            Button { vm.skip() } label: {
                                Image(systemName: "forward.fill").font(.system(size: 12)).foregroundColor(.white)
                                    .frame(width: 32, height: 32).background(th.s).cornerRadius(8)
                            }
                        }
                        Button { vm.toggle() } label: {
                            Text(vm.playing ? "Pause" : "Play").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8).background(th.a).cornerRadius(10)
                        }
                    }.padding(20).background(th.card).cornerRadius(20).padding(.horizontal)
                    
                    Button {
                        showAmbient = true
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "waveform").font(.system(size: 24)).foregroundColor(.white)
                                .frame(width: 50, height: 50).background(th.s).cornerRadius(12)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ambient Sounds").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                                Text(vm.ambientPlaying ? "🔊 \(vm.selectedAmbient)" : "🔇 \(vm.selectedAmbient)").font(.system(size: 12)).foregroundColor(th.s).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(th.s)
                        }.padding(20).background(th.card).cornerRadius(20)
                    }.padding(.horizontal)
                    
                    let st = vm.today()
                    HStack(spacing: 0) {
                        VStack(spacing: 8) {
                            Text("\(st.0)").font(.system(size: 28, weight: .bold)).foregroundColor(th.p)
                            Text("Sessions").font(.system(size: 12, weight: .semibold)).foregroundColor(th.t.opacity(0.7)).textCase(.uppercase)
                        }.frame(maxWidth: .infinity)
                        Divider().frame(height: 40)
                        VStack(spacing: 8) {
                            Text("\(st.1)").font(.system(size: 28, weight: .bold)).foregroundColor(th.s)
                            Text("Minutes").font(.system(size: 12, weight: .semibold)).foregroundColor(th.t.opacity(0.7)).textCase(.uppercase)
                        }.frame(maxWidth: .infinity)
                    }.padding(20).background(th.card).cornerRadius(16).padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }.padding(.top)
            }
        }
        .sheet(isPresented: $showSet) { SetView(vm: vm, th: th) }
        .sheet(isPresented: $showStat) { StatView(vm: vm, th: th) }
        .sheet(isPresented: $vm.showCustom) { CustView(vm: vm, th: th) }
        .sheet(isPresented: $showAmbient) { AmbientSoundsView(vm: vm, th: th) }
    }
}

struct NewCat: View {
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    let run: Bool
    let streak: Int
    @State private var blink = false
    @State private var tail = false
    
    var catState: String {
        if streak >= 3 { return "happy" }
        if streak >= 1 { return "neutral" }
        return "sleepy"
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 35)
                .fill(th.p.opacity(0.3))
                .frame(width: 95, height: 115)
                .scaleEffect(run ? 1.02 : 1)
                .animation(run ? .easeInOut(duration: 2).repeatForever() : .default, value: run)
            
            Circle()
                .fill(th.p.opacity(0.3))
                .frame(width: 80, height: 80)
                .offset(y: -48)
            
            Triangle()
                .fill(th.p.opacity(0.35))
                .frame(width: 24, height: 28)
                .offset(x: -25, y: -75)
            
            Triangle()
                .fill(th.s.opacity(0.4))
                .frame(width: 15, height: 18)
                .offset(x: -25, y: -73)
            
            Triangle()
                .fill(th.p.opacity(0.35))
                .frame(width: 24, height: 28)
                .offset(x: 25, y: -75)
            
            Triangle()
                .fill(th.s.opacity(0.4))
                .frame(width: 15, height: 18)
                .offset(x: 25, y: -73)
            
            // Eyes - state dependent
            if catState == "sleepy" {
                // Sleepy eyes (small, half-closed)
                if !blink {
                    Capsule()
                        .fill(th.t)
                        .frame(width: 12, height: 3)
                        .offset(x: -16, y: -50)
                    
                    Capsule()
                        .fill(th.t)
                        .frame(width: 12, height: 3)
                        .offset(x: 16, y: -50)
                } else {
                    Capsule()
                        .fill(th.t)
                        .frame(width: 12, height: 1)
                        .offset(x: -16, y: -50)
                    
                    Capsule()
                        .fill(th.t)
                        .frame(width: 12, height: 1)
                        .offset(x: 16, y: -50)
                }
            } else if catState == "happy" {
                // Happy eyes (big, sparkly)
                if !blink {
                    Circle()
                        .fill(th.t)
                        .frame(width: 12, height: 12)
                        .offset(x: -16, y: -50)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                        .offset(x: -14, y: -52)
                    
                    Circle()
                        .fill(th.t)
                        .frame(width: 12, height: 12)
                        .offset(x: 16, y: -50)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                        .offset(x: 18, y: -52)
                } else {
                    Capsule()
                        .fill(th.t)
                        .frame(width: 14, height: 2)
                        .offset(x: -16, y: -50)
                    
                    Capsule()
                        .fill(th.t)
                        .frame(width: 14, height: 2)
                        .offset(x: 16, y: -50)
                }
            } else {
                // Neutral eyes (normal)
                if !blink {
                    Circle()
                        .fill(th.t)
                        .frame(width: 10, height: 10)
                        .offset(x: -16, y: -50)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 3, height: 3)
                        .offset(x: -14, y: -52)
                    
                    Circle()
                        .fill(th.t)
                        .frame(width: 10, height: 10)
                        .offset(x: 16, y: -50)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 3, height: 3)
                        .offset(x: 18, y: -52)
                } else {
                    Capsule()
                        .fill(th.t)
                        .frame(width: 12, height: 2)
                        .offset(x: -16, y: -50)
                    
                    Capsule()
                        .fill(th.t)
                        .frame(width: 12, height: 2)
                        .offset(x: 16, y: -50)
                }
            }
            
            // Nose
            Circle()
                .fill(th.a)
                .frame(width: 6, height: 6)
                .offset(y: -41)
            
            // Paws
            Circle()
                .fill(th.p.opacity(0.3))
                .frame(width: 28, height: 28)
                .offset(x: -25, y: 50)
            
            Circle()
                .fill(th.p.opacity(0.3))
                .frame(width: 28, height: 28)
                .offset(x: 25, y: 50)
            
            // Tail
            Capsule()
                .fill(th.p.opacity(0.3))
                .frame(width: 14, height: 60)
                .rotationEffect(.degrees(25 + (tail ? 10 : -10)))
                .offset(x: 50, y: 28)
                .animation(.easeInOut(duration: catState == "happy" ? 1.0 : 1.5).repeatForever(), value: tail)
        }
        .onAppear {
            tail = true
            Timer.scheduledTimer(withTimeInterval: catState == "sleepy" ? 5 : 3, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.15)) { blink = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.15)) { blink = false }
                }
            }
        }
    }
}

struct AmbientSoundsView: View {
    @ObservedObject var vm: VM
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    @Environment(\.dismiss) var d
    
    let sounds = [
        ("Silence", "speaker.slash.fill", Color.gray),
        ("Rain", "cloud.rain.fill", Color.blue),
        ("Fireplace", "flame.fill", Color.orange),
        ("White Noise", "waveform", Color.purple),
        ("Cafe", "cup.and.saucer.fill", Color.brown)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                th.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(sounds, id: \.0) { sound in
                            Button {
                                if sound.0 == "Silence" {
                                    vm.stopAmbient()
                                    vm.selectedAmbient = "Silence"
                                    UserDefaults.standard.set("Silence", forKey: "selectedAmbient")
                                } else {
                                    vm.playAmbient(sound.0)
                                }
                            } label: {
                                HStack(spacing: 15) {
                                    Image(systemName: sound.1)
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(sound.2)
                                        .cornerRadius(12)
                                    
                                    Text(sound.0)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(th.t)
                                    
                                    Spacer()
                                    
                                    if vm.selectedAmbient == sound.0 {
                                        Image(systemName: vm.ambientPlaying && sound.0 != "Silence" ? "speaker.wave.3.fill" : "checkmark.circle.fill")
                                            .foregroundColor(th.p)
                                            .font(.system(size: 22))
                                    }
                                }
                                .padding(20)
                                .background(vm.selectedAmbient == sound.0 ? th.card : th.card.opacity(0.5))
                                .cornerRadius(16)
                            }
                        }
                        
                        VStack(spacing: 8) {
                            Image(systemName: "info.circle").font(.system(size: 20)).foregroundColor(th.s)
                            Text("Ambient sounds loop continuously and work independently of the timer")
                                .font(.system(size: 13))
                                .foregroundColor(th.t.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .background(th.card.opacity(0.5))
                        .cornerRadius(16)
                    }.padding()
                }
            }
            .navigationTitle("Ambient Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { d() }.foregroundColor(th.p)
                }
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CustView: View {
    @ObservedObject var vm: VM
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    @Environment(\.dismiss) var d
    
    var body: some View {
        NavigationView {
            ZStack {
                th.bg.ignoresSafeArea()
                VStack(spacing: 30) {
                    Spacer()
                    Image(systemName: "timer").font(.system(size: 60)).foregroundColor(th.p)
                    Text("Custom Time").font(.system(size: 28, weight: .bold)).foregroundColor(th.t)
                    Text("1-180 minutes").font(.system(size: 16)).foregroundColor(th.s)
                    TextField("", text: $vm.custom).font(.system(size: 48, weight: .bold)).foregroundColor(th.t)
                        .multilineTextAlignment(.center).keyboardType(.numberPad).padding(24).background(th.card).cornerRadius(20).padding(.horizontal, 40)
                    Button { vm.setCustom(); d() } label: {
                        Text("Set").font(.system(size: 20, weight: .bold)).foregroundColor(.white).frame(maxWidth: .infinity)
                            .padding(.vertical, 18).background(th.p).cornerRadius(16)
                    }.padding(.horizontal, 40).disabled(vm.custom.isEmpty).opacity(vm.custom.isEmpty ? 0.5 : 1)
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Cancel") { vm.custom = ""; d() }.foregroundColor(th.p) } }
        }
    }
}

struct BreakSettingsView: View {
    @ObservedObject var vm: VM
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    @Environment(\.dismiss) var d
    
    var body: some View {
        NavigationView {
            ZStack {
                th.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Short Break").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                            HStack(spacing: 10) {
                                ForEach([3, 5, 10], id: \.self) { m in
                                    Button {
                                        vm.shortBreakDuration = m
                                        vm.saveBreakSettings()
                                    } label: {
                                        Text("\(m) min").font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(vm.shortBreakDuration == m ? .white : th.t)
                                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                                            .background(vm.shortBreakDuration == m ? th.p : th.card)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }.padding(20).background(th.card).cornerRadius(16)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Long Break").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                            HStack(spacing: 10) {
                                ForEach([15, 20, 30], id: \.self) { m in
                                    Button {
                                        vm.longBreakDuration = m
                                        vm.saveBreakSettings()
                                    } label: {
                                        Text("\(m) min").font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(vm.longBreakDuration == m ? .white : th.t)
                                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                                            .background(vm.longBreakDuration == m ? th.s : th.card)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }.padding(20).background(th.card).cornerRadius(16)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sessions until Long Break").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                            HStack(spacing: 10) {
                                ForEach([2, 4, 6], id: \.self) { n in
                                    Button {
                                        vm.sessionsUntilLongBreak = n
                                        vm.saveBreakSettings()
                                    } label: {
                                        Text("\(n)").font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(vm.sessionsUntilLongBreak == n ? .white : th.t)
                                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                                            .background(vm.sessionsUntilLongBreak == n ? th.a : th.card)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }.padding(20).background(th.card).cornerRadius(16)
                        
                        VStack(spacing: 8) {
                            Image(systemName: "info.circle").font(.system(size: 24)).foregroundColor(th.s)
                            Text("Complete \(vm.sessionsUntilLongBreak) focus sessions to earn a \(vm.longBreakDuration)-minute long break")
                                .font(.system(size: 13)).foregroundColor(th.t.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }.padding(20).background(th.card.opacity(0.5)).cornerRadius(16)
                    }.padding()
                }
            }
            .navigationTitle("Break Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { d() }.foregroundColor(th.p) } }
        }
    }
}

struct SetView: View {
    @ObservedObject var vm: VM
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    @Environment(\.dismiss) var d
    @State private var showBreakSettings = false
    @State private var showAbout = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 15) {
                        Button { showBreakSettings = true } label: {
                            HStack {
                                Image(systemName: "cup.and.saucer.fill").font(.system(size: 20)).foregroundColor(th.p)
                                    .frame(width: 40, height: 40).background(th.p.opacity(0.15)).cornerRadius(10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Break Settings").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                                    Text("\(vm.shortBreakDuration) / \(vm.longBreakDuration) min").font(.system(size: 13)).foregroundColor(th.s)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(th.s)
                            }.padding(16).background(th.card).cornerRadius(16)
                        }
                        
                        Button { showAbout = true } label: {
                            HStack {
                                Image(systemName: "info.circle.fill").font(.system(size: 20)).foregroundColor(th.s)
                                    .frame(width: 40, height: 40).background(th.s.opacity(0.15)).cornerRadius(10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("About").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                                    Text("App info & credits").font(.system(size: 13)).foregroundColor(th.s)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(th.s)
                            }.padding(16).background(th.card).cornerRadius(16)
                        }
                        
                        Text("Themes").font(.system(size: 14, weight: .semibold)).foregroundColor(th.t.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).padding(.horizontal, 4)
                        
                        ForEach(0..<4, id: \.self) { i in
                            let t = themes[i]
                            Button { vm.themeIdx = i; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { d() } } label: {
                                HStack {
                                    Text(themeNames[i]).font(.system(size: 16, weight: .semibold)).foregroundColor(t.t)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Circle().fill(t.p).frame(width: 24, height: 24)
                                        Circle().fill(t.s).frame(width: 24, height: 24)
                                        Circle().fill(t.a).frame(width: 24, height: 24)
                                    }
                                }.padding(20).background(t.card).cornerRadius(16)
                            }
                        }
                    }.padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { d() }.foregroundColor(th.p) } }
            .sheet(isPresented: $showBreakSettings) { BreakSettingsView(vm: vm, th: th) }
            .sheet(isPresented: $showAbout) { AboutView(th: th) }
        }
    }
}

struct AboutView: View {
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    @Environment(\.dismiss) var d
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                th.bg.ignoresSafeArea()
                VStack(spacing: 30) {
                    Spacer()
                    
                    // App Icon
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [th.p, th.s],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "timer")
                            .font(.system(size: 50, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    // App Name
                    Text("LofiumFocus")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(th.t)
                    
                    // Version
                    Text("Version \(appVersion)")
                        .font(.system(size: 16))
                        .foregroundColor(th.s)
                    
                    Spacer()
                    
                    // Credits
                    VStack(spacing: 15) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundColor(th.p)
                            Text("Created by")
                                .font(.system(size: 16))
                                .foregroundColor(th.t.opacity(0.7))
                        }
                        
                        Text("giblecdg")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(th.p)
                        
                        Text("© 2026")
                            .font(.system(size: 14))
                            .foregroundColor(th.s)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity)
                    .background(th.card)
                    .cornerRadius(24)
                    .padding(.horizontal, 30)
                    
                    Spacer()
                    
                    // Tagline
                    Text("Stay focused, stay lofi 🎧")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(th.t.opacity(0.6))
                        .italic()
                    
                    Spacer()
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { d() }.foregroundColor(th.p)
                }
            }
        }
    }
}

struct StatView: View {
    @ObservedObject var vm: VM
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    @Environment(\.dismiss) var d
    @State private var showWeekly = false
    
    var body: some View {
        NavigationView {
            ZStack {
                th.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        let tot = vm.total()
                        let tod = vm.today()
                        
                        Button {
                            showWeekly = true
                        } label: {
                            HStack {
                                Image(systemName: "calendar").font(.system(size: 20)).foregroundColor(th.p)
                                    .frame(width: 40, height: 40).background(th.p.opacity(0.15)).cornerRadius(10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Weekly Summary").font(.system(size: 16, weight: .semibold)).foregroundColor(th.t)
                                    Text("Last 7 days").font(.system(size: 13)).foregroundColor(th.s)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(th.s)
                            }.padding(16).background(th.card).cornerRadius(16)
                        }
                        
                        HStack {
                            Image(systemName: "flame.fill").font(.system(size: 32)).foregroundColor(.orange)
                                .frame(width: 60, height: 60).background(Color.orange.opacity(0.2)).cornerRadius(16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Streak").font(.system(size: 14, weight: .semibold)).foregroundColor(th.t.opacity(0.7))
                                Text("\(vm.currentStreak)").font(.system(size: 36, weight: .bold)).foregroundColor(.orange)
                                Text("day\(vm.currentStreak == 1 ? "" : "s")").font(.system(size: 13)).foregroundColor(th.s)
                            }
                            Spacer()
                        }.padding(20).background(th.card).cornerRadius(20)
                        
                        HStack {
                            Image(systemName: "flame.fill").font(.system(size: 32)).foregroundColor(th.p)
                                .frame(width: 60, height: 60).background(th.p.opacity(0.2)).cornerRadius(16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Sessions").font(.system(size: 14, weight: .semibold)).foregroundColor(th.t.opacity(0.7))
                                Text("\(tot.0)").font(.system(size: 36, weight: .bold)).foregroundColor(th.p)
                                Text("\(tod.0) today").font(.system(size: 13)).foregroundColor(th.s)
                            }
                            Spacer()
                        }.padding(20).background(th.card).cornerRadius(20)
                        HStack {
                            Image(systemName: "clock.fill").font(.system(size: 32)).foregroundColor(th.s)
                                .frame(width: 60, height: 60).background(th.s.opacity(0.2)).cornerRadius(16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Minutes").font(.system(size: 14, weight: .semibold)).foregroundColor(th.t.opacity(0.7))
                                Text("\(tot.1)").font(.system(size: 36, weight: .bold)).foregroundColor(th.s)
                                Text("\(tod.1) today").font(.system(size: 13)).foregroundColor(th.s)
                            }
                            Spacer()
                        }.padding(20).background(th.card).cornerRadius(20)
                    }.padding()
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { d() }.foregroundColor(th.p) } }
            .sheet(isPresented: $showWeekly) { WeeklySummaryView(vm: vm, th: th) }
        }
    }
}

struct WeeklySummaryView: View {
    @ObservedObject var vm: VM
    let th: (bg: Color, card: Color, p: Color, s: Color, a: Color, t: Color)
    @Environment(\.dismiss) var d
    
    var body: some View {
        NavigationView {
            ZStack {
                th.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        let stats = vm.weeklyStats()
                        let weekData = vm.weeklyData()
                        let maxMinutes = weekData.map(\.minutes).max() ?? 1
                        
                        // Stats Cards
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            VStack(spacing: 8) {
                                Text("\(stats.sessions)").font(.system(size: 32, weight: .bold)).foregroundColor(th.p)
                                Text("Sessions").font(.system(size: 12, weight: .semibold)).foregroundColor(th.t.opacity(0.7)).textCase(.uppercase)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(th.card)
                            .cornerRadius(16)
                            
                            VStack(spacing: 8) {
                                Text("\(stats.minutes)").font(.system(size: 32, weight: .bold)).foregroundColor(th.s)
                                Text("Minutes").font(.system(size: 12, weight: .semibold)).foregroundColor(th.t.opacity(0.7)).textCase(.uppercase)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(th.card)
                            .cornerRadius(16)
                            
                            VStack(spacing: 8) {
                                Text("\(stats.avgPerDay)").font(.system(size: 32, weight: .bold)).foregroundColor(th.a)
                                Text("Avg/Day").font(.system(size: 12, weight: .semibold)).foregroundColor(th.t.opacity(0.7)).textCase(.uppercase)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(th.card)
                            .cornerRadius(16)
                            
                            VStack(spacing: 8) {
                                Text(stats.bestDay).font(.system(size: 32, weight: .bold)).foregroundColor(th.p)
                                Text("Best Day").font(.system(size: 12, weight: .semibold)).foregroundColor(th.t.opacity(0.7)).textCase(.uppercase)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(th.card)
                            .cornerRadius(16)
                        }
                        
                        // Bar Chart
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Daily Breakdown").font(.system(size: 18, weight: .bold)).foregroundColor(th.t)
                            
                            HStack(alignment: .bottom, spacing: 12) {
                                ForEach(weekData, id: \.day) { data in
                                    VStack(spacing: 8) {
                                        ZStack(alignment: .bottom) {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(th.card)
                                                .frame(height: 150)
                                            
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(LinearGradient(
                                                    colors: [th.p, th.s],
                                                    startPoint: .bottom,
                                                    endPoint: .top
                                                ))
                                                .frame(height: max(10, CGFloat(data.minutes) / CGFloat(maxMinutes) * 150))
                                        }
                                        
                                        Text(data.day).font(.system(size: 11, weight: .semibold)).foregroundColor(th.t.opacity(0.7))
                                        Text("\(data.minutes)").font(.system(size: 10, weight: .bold)).foregroundColor(th.s)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(20)
                        .background(th.card.opacity(0.3))
                        .cornerRadius(20)
                    }.padding()
                }
            }
            .navigationTitle("Weekly Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { d() }.foregroundColor(th.p)
                }
            }
        }
    }
}
