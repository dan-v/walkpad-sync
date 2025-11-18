#!/bin/bash

echo "🔍 Verifying iOS app files after git pull..."
echo ""

REQUIRED_FILES=(
    "TreadmillSync/Models/ServerConfig.swift"
    "TreadmillSync/Models/Workout.swift"
    "TreadmillSync/Services/APIClient.swift"
    "TreadmillSync/Services/HealthKitManager.swift"
    "TreadmillSync/Services/SyncManager.swift"
    "TreadmillSync/Views/ContentView.swift"
    "TreadmillSync/Views/WorkoutListView.swift"
    "TreadmillSync/Views/WorkoutDetailView.swift"
    "TreadmillSync/Views/SettingsView.swift"
    "TreadmillSync/TreadmillSyncApp.swift"
)

ALL_GOOD=true

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        lines=$(wc -l < "$file")
        echo "✅ $file ($lines lines)"
    else
        echo "❌ MISSING: $file"
        ALL_GOOD=false
    fi
done

echo ""
if [ "$ALL_GOOD" = true ]; then
    echo "✨ All required files present!"
    echo ""
    echo "Next steps:"
    echo "1. Open TreadmillSync.xcodeproj in Xcode"
    echo "2. Add Models/ and Services/ folders to the project"
    echo "3. Build and run!"
else
    echo "⚠️  Some files are missing. Try: git pull --rebase"
fi
