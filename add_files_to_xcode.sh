#!/bin/bash

# Files to add to Xcode project
FILES=(
    "TreadmillSync/Models/ServerConfig.swift"
    "TreadmillSync/Models/Workout.swift"
    "TreadmillSync/Services/APIClient.swift"
    "TreadmillSync/Services/HealthKitManager.swift"
    "TreadmillSync/Services/SyncManager.swift"
    "TreadmillSync/Views/ContentView.swift"
    "TreadmillSync/Views/WorkoutListView.swift"
    "TreadmillSync/Views/WorkoutDetailView.swift"
)

PROJECT="TreadmillSync.xcodeproj"

echo "Files to add to Xcode project:"
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (missing)"
    fi
done

echo ""
echo "To add these files to your Xcode project:"
echo "1. Open TreadmillSync.xcodeproj in Xcode"
echo "2. Right-click on TreadmillSync folder in Project Navigator"
echo "3. Select 'Add Files to \"TreadmillSync\"...'"
echo "4. Select these folders:"
echo "   - TreadmillSync/Models"
echo "   - TreadmillSync/Services"
echo "5. Make sure 'Copy items if needed' is UNCHECKED"
echo "6. Make sure 'Create groups' is selected"
echo "7. Make sure target 'TreadmillSync' is checked"
echo "8. Click Add"
echo ""
echo "Alternative: You can also drag-and-drop the folders from Finder into Xcode"
