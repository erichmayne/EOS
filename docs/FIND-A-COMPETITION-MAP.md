# "Find a Competition" — Map Discovery Feature

**Created:** April 7, 2026
**Status:** Feasibility Report / Plan
**Author:** AI-assisted

---

## Feature Summary

Add a "Find a Competition" section to the Compete tab with an interactive Apple Maps-style map showing public competitions pinned to their locations. Users can browse the map, search by name, or filter by location to discover and join open lobbies.

---

## Feasibility: YES — Very Doable

SwiftUI's MapKit integration (iOS 17+) is mature and purpose-built for this. The `Map` view supports custom `Annotation` views with any SwiftUI content as pins, selection handling, region-based filtering, and all standard map controls. No third-party libraries needed — this is pure Apple frameworks.

**Key frameworks:**
- `MapKit` for SwiftUI — `Map`, `Annotation`, `MapCameraPosition`, `MKLocalSearch`
- `CoreLocation` — `CLLocationManager` for user's current location, `CLGeocoder` for address → coordinate conversion

---

## What Needs to Change

### 1. Database: `competitions` Table

Add these columns:

| Column | Type | Purpose |
|--------|------|---------|
| `latitude` | `DOUBLE PRECISION` | Competition location lat |
| `longitude` | `DOUBLE PRECISION` | Competition location long |
| `location_name` | `TEXT` | Human-readable location label (e.g. "Austin, TX") |
| `visibility` | `TEXT DEFAULT 'private'` | `'public'` or `'private'` — controls map discoverability |

**Migration SQL:**

```sql
ALTER TABLE competitions
  ADD COLUMN latitude DOUBLE PRECISION,
  ADD COLUMN longitude DOUBLE PRECISION,
  ADD COLUMN location_name TEXT,
  ADD COLUMN visibility TEXT DEFAULT 'private';
```

Existing competitions get `visibility = 'private'` by default, so nothing breaks. Only new competitions explicitly set to public will appear on the map.

### 2. Backend: New Endpoint + Modified Create

**New endpoint — `GET /compete/discover`**

Returns all public, joinable competitions with location data.

```
GET /compete/discover?lat=30.27&lng=-97.74&radius=50&search=austin
```

Query params (all optional):
- `lat`, `lng` — center point for distance sorting
- `radius` — miles to filter (default: no limit, just sort by distance)
- `search` — text search against competition name or location_name
- `status` — filter by status (default: `pending` only, i.e. open lobbies)

Response:
```json
{
  "competitions": [
    {
      "id": "uuid",
      "name": "Austin Runners 5K Challenge",
      "objective_type": "run",
      "scoring_type": "race",
      "duration_days": 30,
      "buy_in_amount": 20,
      "target_value": 3.1,
      "latitude": 30.2672,
      "longitude": -97.7431,
      "location_name": "Austin, TX",
      "participant_count": 4,
      "creator_name": "Erich",
      "invite_code": "ABC123",
      "created_at": "2026-04-07T..."
    }
  ]
}
```

**Modify `POST /compete/create`:**

Accept new fields in the request body:
- `latitude` (number, optional)
- `longitude` (number, optional)
- `locationName` (string, optional)
- `visibility` ("public" | "private", default "private")

Insert them into the `competitions` row on creation. Public competitions with no location data are still searchable by name but won't appear on the map.

### 3. iOS: Create Competition View Changes

Add to `CreateCompetitionView`:

**Visibility picker** (new section in the form):
- "Private" (default) — only joinable via invite code
- "Public" — appears on the map for anyone to find and join

**Location picker** (shown when visibility = public):
- Text field with `MKLocalSearchCompleter` for autocomplete suggestions (type "Austin" → "Austin, TX" appears)
- On selection, resolve to lat/long via `MKLocalSearch`
- Optional: "Use My Location" button using `CLLocationManager`
- Display selected location on a small inline map preview

**Updated `createCompetition()` body:**
```swift
let body: [String: Any] = [
    // ...existing fields...
    "visibility": visibility,           // "public" or "private"
    "latitude": selectedLatitude,        // Double?
    "longitude": selectedLongitude,      // Double?
    "locationName": selectedLocationName // String?
]
```

### 4. iOS: Find a Competition View (NEW)

New `FindCompetitionView` — the main feature addition. Accessed from the Compete tab.

**Layout:**

```
┌──────────────────────────────────┐
│  ← Find a Competition            │  (nav bar)
├──────────────────────────────────┤
│  🔍 Search competitions...       │  (search bar)
├──────────────────────────────────┤
│                                  │
│         [  MAP VIEW  ]           │  (Apple Maps with pins)
│     📍    📍                     │
│           📍  📍                 │
│       📍                         │
│                                  │
├──────────────────────────────────┤
│  ┌─────────────────────────────┐ │
│  │ 🏃 Austin 5K Challenge      │ │  (scrollable list below map)
│  │ Race · $20 buy-in · 4/8    │ │
│  │ Austin, TX · 2.3 mi away   │ │
│  └─────────────────────────────┘ │
│  ┌─────────────────────────────┐ │
│  │ 💪 NYC Push-Up Battle       │ │
│  │ 30 days · Free · 6/10      │ │
│  │ New York, NY · 1,200 mi    │ │
│  └─────────────────────────────┘ │
└──────────────────────────────────┘
```

**Interactions:**
- Map shows gold pins for each public competition
- Tapping a pin shows a callout card with competition details + "Join" button
- Search bar filters by competition name or location
- List below map shows all results, sorted by distance from user
- Tapping a list item centers the map on that pin
- Pull-to-refresh or map drag to load competitions in the visible region

**Map pin design:**
- Gold trophy icon pin for competitions with buy-in
- Standard gold dot for free competitions
- Selected pin scales up with a detail card overlay

**SwiftUI implementation sketch:**

```swift
struct FindCompetitionView: View {
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var competitions: [DiscoverableCompetition] = []
    @State private var selectedCompetition: DiscoverableCompetition?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Map
            Map(position: $position, selection: $selectedCompetition) {
                ForEach(competitions) { comp in
                    Annotation(comp.name, coordinate: comp.coordinate) {
                        CompetitionMapPin(comp: comp, isSelected: selectedCompetition?.id == comp.id)
                    }
                    .tag(comp)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .frame(height: 350)

            // List
            competitionList
        }
    }
}
```

### 5. iOS: Compete Tab Integration

The `CompeteView` currently has:
- Empty state with "Create" / "Join with Code" buttons
- Active/pending competition list

**Add a third option:**
- "Find a Competition" button in the toolbar or empty state
- Opens `FindCompetitionView` as a sheet or navigation push
- Could also add a segmented control: "My Competitions" | "Discover"

---

## Size of Addition

| Component | Effort | Lines (est.) |
|-----------|--------|-------------|
| **SQL migration** | Small | ~5 lines |
| **Backend: modify `/compete/create`** | Small | ~10 lines (accept + insert new fields) |
| **Backend: new `GET /compete/discover`** | Medium | ~60-80 lines (query, distance calc, search, response) |
| **iOS: Visibility + location picker in CreateCompetitionView** | Medium | ~150-200 lines |
| **iOS: FindCompetitionView (map + list + search)** | Large | ~400-500 lines |
| **iOS: Map pin component** | Small | ~40-60 lines |
| **iOS: CompeteView integration** | Small | ~30-50 lines |
| **iOS: Data model for discoverable competition** | Small | ~30 lines |

**Total estimate: ~750-950 lines of new code** across backend + iOS.

**Complexity: Medium.** No new frameworks to learn — MapKit is well-documented, the database change is a simple `ALTER TABLE`, and the backend endpoint is a straightforward query. The iOS map view is the bulk of the work but it's standard SwiftUI MapKit.

**Timeline estimate:** 1-2 focused sessions to build, 1 session to polish.

---

## Good Ideas & Enhancements

### Core UX

1. **"Near Me" default view** — Map opens centered on the user's location with nearby public competitions visible. If no competitions are nearby, zoom out to show the closest ones.

2. **Participant count as social proof** — Show "4/8 joined" or "3 runners" on each pin callout. Competitions that are almost full feel more urgent.

3. **"Starting Soon" badge** — Highlight lobbies where the creator is likely to start soon (e.g. 4+ participants already joined). Creates urgency.

4. **Quick Join from map** — Tap a pin → see the details card → "Join" button right there. Don't force navigation to a separate sheet. Reduce friction to joining.

5. **Search autocomplete** — Use `MKLocalSearchCompleter` for the location/search field. Typing "San Fr..." auto-suggests "San Francisco, CA". Also search against competition names.

### Map Design

6. **Clustered pins** — When zoomed out, cluster nearby competitions into a single pin with a count badge ("5 competitions"). Expand on zoom. MapKit supports `MKClusterAnnotation` for this.

7. **Heat zones** — Optional: show colored circles/halos around areas with many competitions. More competitions = brighter glow. Signals active communities.

8. **Filter chips** — Below the search bar, horizontal scroll of filter chips: "Run", "Pushups", "Free Entry", "Buy-In", "Race Mode", "Starting Soon". Tap to toggle.

9. **Map style toggle** — Small button to switch between standard and satellite view. Some users prefer seeing terrain for running competitions.

### Competition Discovery

10. **"Featured" or "Popular" section** — Above the map, show a horizontal carousel of trending/popular competitions (most participants, highest buy-in, starting soonest).

11. **Location-based notifications** — Future: "A new competition was created near you!" Push notification when a public competition is created within X miles.

12. **Share competition location** — Public competitions get a shareable deep link: `live-eos.com/compete/ABC123` that shows the competition on a web map and prompts app download.

13. **Creator reputation** — Show how many competitions the creator has run and their completion rate. Builds trust for buy-in competitions with strangers.

### Privacy & Safety

14. **Location precision** — Don't store exact coordinates. Snap to city/neighborhood level (~0.01 degree precision, roughly 0.7 miles). Nobody needs to know the creator's home address.

15. **Report/flag** — Allow reporting inappropriate competition names since public competitions are visible to all users.

16. **Minimum participants for public** — Consider requiring public competitions to allow at least 3-4 participants. A "public" 2-person competition doesn't make much sense.

### Data & Growth

17. **Empty state for no nearby competitions** — Instead of a blank map, show: "No competitions near you yet. Be the first!" with a prominent "Create Public Competition" button. Turn every empty map into a creation prompt.

18. **Activity heatmap over time** — Track which cities/regions have the most competition activity. Use this data for marketing ("RunMatch is trending in Austin!").

19. **Competition templates** — Pre-made public competition types: "30-Day 1-Mile Challenge", "Weekend Warrior 5K", "100 Push-Ups Daily". Let users launch popular formats with one tap and auto-set to public.

---

## Info.plist Requirements

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>RunMatch uses your location to show competitions near you.</string>
```

This is a "when in use" permission only — no background location needed. The permission prompt only appears when the user opens the Find Competition map.

---

## Risk & Considerations

| Risk | Mitigation |
|------|------------|
| **Few public competitions at launch** | Empty state prompts creation; seed with example competitions; make "public" the suggested default for new competitions |
| **Inappropriate competition names** | Report/flag system; name moderation (profanity filter) |
| **Location privacy** | Snap to city level; don't expose creator's exact location |
| **App Store review** | MapKit is first-party Apple; no gambling concerns since competitions are already approved; location permission is standard |
| **Performance with many pins** | Cluster annotations; paginate the discover endpoint; only fetch competitions in the visible map region |

---

## Phased Rollout

### Phase 1: Foundation (MVP)
- Add `visibility`, `latitude`, `longitude`, `location_name` to `competitions` table
- Add Public/Private toggle to CreateCompetitionView
- Add location search (MKLocalSearchCompleter) for public competitions
- Build `GET /compete/discover` endpoint
- Build basic `FindCompetitionView` with map + list
- Add "Find a Competition" button to CompeteView

### Phase 2: Polish
- Map pin clustering
- Filter chips (objective type, free/paid, etc.)
- "Near Me" sort
- Search by name + location
- Quick Join from map callout

### Phase 3: Growth
- Featured/trending competitions carousel
- Location-based push notifications
- Competition templates
- Share deep links with map preview
- Creator reputation badges
