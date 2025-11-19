import SwiftUI

struct LiveWorkoutBanner: View {
    let liveData: LiveWorkoutResponse
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main banner
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Pulsing indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.green.opacity(0.3), lineWidth: 3)
                                .scaleEffect(1.4)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout in Progress")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        if let metrics = liveData.currentMetrics {
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "speedometer")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                    Text("\(metrics.speedFormatted) mph")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: "figure.walk")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("\(metrics.distanceFormatted) mi")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: "shoeprints.fill")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                    Text("\(metrics.stepsFormatted)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text("\(metrics.caloriesFormatted) cal")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.1))
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded, let metrics = liveData.currentMetrics {
                VStack(spacing: 16) {
                    // Metrics grid (2x2)
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        MetricCard(
                            icon: "speedometer",
                            label: "Speed",
                            value: metrics.speedFormatted,
                            unit: "mph",
                            color: .blue
                        )

                        MetricCard(
                            icon: "figure.walk",
                            label: "Distance",
                            value: metrics.distanceFormatted,
                            unit: "mi",
                            color: .green
                        )

                        MetricCard(
                            icon: "shoeprints.fill",
                            label: "Steps",
                            value: metrics.stepsFormatted,
                            unit: "",
                            color: .purple
                        )

                        MetricCard(
                            icon: "flame.fill",
                            label: "Calories",
                            value: metrics.caloriesFormatted,
                            unit: "kcal",
                            color: .orange
                        )
                    }

                    // Start time
                    if let workout = liveData.workout, let start = workout.start {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("Started \(timeAgo(from: start))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
            }
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = minutes / 60

        if hours > 0 {
            return "\(hours)h \(minutes % 60)m ago"
        } else if minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "just now"
        }
    }
}

struct MetricBadge: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
            Text(unit)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
    }
}

struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)

                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
