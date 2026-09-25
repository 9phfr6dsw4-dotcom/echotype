import AppKit
import EchoTypeCore
import SwiftUI

struct HomeView: View {
    @Environment(EchoTypeRuntime.self) private var runtime

    private var history: TranscriptHistoryViewModel { runtime.history }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EchoType")
                        .font(.largeTitle.weight(.semibold))
                    Text("Private, on-device dictation")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                SpeechDictationPanel()
                stats
                todaySection
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 580)
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
            metric("Words", value: history.totalWordCount.formatted(), symbol: "text.word.spacing")
            metric("Sessions", value: history.records.count.formatted(), symbol: "waveform")
            metric("Today", value: history.todayWordCount.formatted(), symbol: "calendar")
            metric("Time saved*", value: formattedTime(history.estimatedTimeSaved), symbol: "clock")
            metric("Daily streak", value: "\(history.dailyStreak) days", symbol: "flame")
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's transcripts")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("*Estimated against typing at 40 words per minute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = history.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if history.todayRecords.isEmpty {
                ContentUnavailableView(
                    history.settings.historyEnabled ? "No transcripts today" : "Transcript history is off",
                    systemImage: "text.bubble",
                    description: Text(history.settings.historyEnabled
                        ? "Your saved transcripts will appear here."
                        : "Turn on local transcript history in Settings to save transcripts.")
                )
                .frame(minHeight: 170)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(history.todayRecords) { record in
                        transcriptCard(record)
                    }
                }
            }
        }
    }

    private func transcriptCard(_ record: TranscriptRecord) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(record.timestamp.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text("\(wordCount(record.text)) words")
                    Text("·")
                    Text(formattedTime(record.duration))
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.text, forType: .string)
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(record.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}
