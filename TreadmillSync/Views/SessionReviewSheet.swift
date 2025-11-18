//
//  SessionReviewSheet.swift
//  TreadmillSync
//
//  Review screen before saving workout to Apple Health
//

import SwiftUI

struct SessionReviewSheet: View {
    let session: DailySession
    @Binding var isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero Stats
                    VStack(spacing: 8) {
                        Text("Ready to Save")
                            .font(.title2.bold())

                        Text("Review your workout before saving to Apple Health")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Summary Card
                    VStack(spacing: 20) {
                        // Big Number - Steps
                        VStack(spacing: 4) {
                            Text("\(session.totalSteps)")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            Text("Total Steps")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        // Other Stats
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                            ReviewStat(
                                icon: "map.fill",
                                label: "Distance",
                                value: String(format: "%.2f", session.totalDistanceMiles),
                                unit: "miles",
                                color: .green
                            )

                            ReviewStat(
                                icon: "flame.fill",
                                label: "Calories",
                                value: "\(session.totalCalories)",
                                unit: "kcal",
                                color: .orange
                            )

                            ReviewStat(
                                icon: "clock.fill",
                                label: "Duration",
                                value: session.formattedDuration,
                                unit: "",
                                color: .purple
                            )

                            ReviewStat(
                                icon: "figure.walk.circle.fill",
                                label: "Sessions",
                                value: "\(session.activitySegments.count)",
                                unit: session.activitySegments.count == 1 ? "walk" : "walks",
                                color: .blue
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // Timeline
                    if !session.activitySegments.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Activity Breakdown")
                                .font(.headline)

                            ForEach(Array(session.activitySegments.enumerated()), id: \.element.id) { index, segment in
                                SegmentRow(index: index + 1, segment: segment)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }

                    // Metadata Info
                    VStack(alignment: .leading, spacing: 12) {
                        Label("What gets saved:", systemImage: "info.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 6) {
                            InfoRow(text: "Indoor walking workout")
                            InfoRow(text: "Steps, distance, and calories")
                            InfoRow(text: "Activity timeline with segments")
                            InfoRow(text: "LifeSpan TR1200B equipment tag")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.secondarySystemBackground))
                    )

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: handleCancel)
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Save Button
                Button(action: onSave) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(isSaving ? "Saving..." : "Save to Apple Health")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .cornerRadius(16)
                }
                .disabled(isSaving)
                .padding()
                .background(Color(.systemBackground).opacity(0.95))
            }
        }
    }

    private func handleCancel() {
        dismiss()
        onCancel()
    }
}

struct ReviewStat: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)

            VStack(spacing: 2) {
                Text(value)
                    .font(.title2.bold().monospacedDigit())

                HStack(spacing: 4) {
                    Text(label)
                    if !unit.isEmpty {
                        Text("(\(unit))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}

struct SegmentRow: View {
    let index: Int
    let segment: DailySession.ActivitySegment

    var body: some View {
        HStack(spacing: 12) {
            // Index
            Text("\(index)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.blue))

            // Time
            VStack(alignment: .leading, spacing: 2) {
                Text("\(segment.startTime, style: .time) - \(segment.endTime, style: .time)")
                    .font(.subheadline.bold().monospacedDigit())

                HStack(spacing: 8) {
                    Text("\(segment.steps) steps")
                    Text("•")
                    Text(String(format: "%.2f mi", segment.distanceMiles))
                    Text("•")
                    Text("\(segment.calories) cal")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
}

struct InfoRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SessionReviewSheet(
        session: DailySession(
            id: UUID(),
            startDate: Date().addingTimeInterval(-7200),
            lastUpdated: Date(),
            totalSteps: 5234,
            totalDistanceMiles: 2.45,
            totalCalories: 287,
            activitySegments: [
                DailySession.ActivitySegment(
                    startTime: Date().addingTimeInterval(-7200),
                    endTime: Date().addingTimeInterval(-5400),
                    steps: 2100,
                    distanceMiles: 1.1,
                    calories: 125
                ),
                DailySession.ActivitySegment(
                    startTime: Date().addingTimeInterval(-3600),
                    endTime: Date(),
                    steps: 3134,
                    distanceMiles: 1.35,
                    calories: 162
                )
            ]
        ),
        isSaving: .constant(false),
        onSave: {},
        onCancel: {}
    )
}
