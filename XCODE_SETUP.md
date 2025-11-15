# iOS Project Setup Instructions

## The project file has been restored. Follow these steps in Xcode:

### Step 1: Pull the latest changes
```bash
cd /path/to/lifespan-app
git pull
```

### Step 2: Open the project
Open `TreadmillSync.xcodeproj` in Xcode (it should open now without errors)

### Step 3: Remove old files (in Xcode)

In the Project Navigator (left sidebar), **select and delete** these files:
- Right-click → **Delete** → Choose **"Remove Reference"** (NOT "Move to Trash")

**Files to remove:**
- `Managers/` folder (entire folder and all its contents)
- `Views/MainView.swift`
- `Views/TabRootView.swift`
- `Views/SessionReviewSheet.swift`
- `Views/SimpleMainView.swift`
- `SimpleTreadmillSyncApp.swift`

### Step 4: Add new files (in Xcode)

1. Right-click on the "TreadmillSync" folder (yellow icon) in Project Navigator
2. Select **"Add Files to 'TreadmillSync'..."**
3. Navigate to your `TreadmillSync` folder
4. **Select these folders** (hold Cmd to select multiple):
   - `Models/`
   - `Services/`
5. Also select these **individual view files**:
   - `Views/ContentView.swift`
   - `Views/WorkoutListView.swift`
   - `Views/WorkoutDetailView.swift`
6. In the dialog, make sure:
   - ✅ **"Create groups"** is selected (NOT "folder references")
   - ✅ **"TreadmillSync" target** is checked
   - ❌ **"Copy items if needed"** is **UNCHECKED**
7. Click **"Add"**

### Step 5: Build
- Press **Cmd+B** to build
- The project should now compile successfully!

## What you should see in Project Navigator:

```
TreadmillSync/
├── TreadmillSyncApp.swift
├── Models/
│   ├── ServerConfig.swift
│   └── Workout.swift
├── Services/
│   ├── APIClient.swift
│   ├── HealthKitManager.swift
│   └── SyncManager.swift
├── Views/
│   ├── ContentView.swift
│   ├── WorkoutListView.swift
│   ├── WorkoutDetailView.swift
│   └── SettingsView.swift
├── Info.plist
└── ... (other config files)
```

## If you still have issues:

Try **Product → Clean Build Folder** (Cmd+Shift+K) then rebuild.
