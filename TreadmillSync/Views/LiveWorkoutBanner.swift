import SwiftUI

struct LiveWorkoutBanner: View {
    let liveData: LiveWorkoutResponse

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text("Workout in Progress")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                if let workout = liveData.workout, let start = workout.start {
                    Text(timeAgo(from: start))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Metrics Grid (2x2)
            if let metrics = liveData.currentMetrics {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    CompactMetricCard(
                        icon: "speedometer",
                        value: metrics.speedFormatted,
                        unit: "mph",
                        color: .green
                    )

                    CompactMetricCard(
                        icon: "figure.walk",
                        value: metrics.distanceFormatted,
                        unit: "mi",
                        color: .blue
                    )

                    CompactMetricCard(
                        icon: "shoeprints.fill",
                        value: metrics.stepsFormatted,
                        unit: "steps",
                        color: .purple
                    )

                    CompactMetricCard(
                        icon: "flame.fill",
                        value: metrics.caloriesFormatted,
                        unit: "cal",
                        color: .orange
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = minutes / 60

        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "now"
        }
    }
}

struct CompactMetricCard: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(8)
    }
}
