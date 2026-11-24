# Firestore Schema — ClearWash Carwash Mobile POS

This schema models multi-outlet carwash operations (bay allocation, service & vehicle catalogs, intake transactions, payments, and shift reconciliation) under `/outlets/{outletId}` in Cloud Firestore.

---

## Collection Hierarchy

```text
/outlets/{outletId}
├── /bays/{bayId}
├── /catalogs/{catalogId}
├── /orders/{orderId}      (Transactions)
└── /shifts/{shiftId}
```

---

## 1. `/outlets/{outletId}`

Outlet metadata and atomic daily queue sequence state.

| Field | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `name` | `string` | `1..120` chars | Outlet display name (e.g., `'ClearWash Outlet Utama'`) |
| `activeBays` | `int` | `0..50` | Number of active washing bays at this outlet |
| `lastQueueDateKey` | `string` (optional) | `YYYY-MM-DD` | Last date key for sequential daily queue numbers |
| `lastQueueSeq` | `int` (optional) | `>= 0` | Last issued daily queue counter for `lastQueueDateKey` |
| `updatedAt` | `timestamp` (optional) | server/client timestamp | Last outlet metadata or queue sequence update |

---

## 2. `/outlets/{outletId}/bays/{bayId}`

Physical washing bays monitored in real time by the queue board.

| Field | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | `string` | `== bayId`, `1..40` chars | Document ID (`'bay_01'`, `'bay_02'`, `'bay_03'`, `'bay_motor_01'`) |
| `name` | `string` | `1..60` chars | Bay label shown on POS (`'BAY 01'`, `'BAY MOTOR 01'`) |
| `supportedType` | `string \| null` | `'mobil' \| 'motor' \| null` | Vehicle type restriction (`null` = universal bay) |
| `status` | `string` | `'available' \| 'occupied' \| 'maintenance'` | Current bay availability status |
| `currentOrderId` | `string \| null` | `<= 80` chars | Currently assigned order ID while occupied |
| `currentPlate` | `string \| null` | `<= 20` chars | License plate of vehicle currently inside bay |
| `operatorName` | `string \| null` | `<= 80` chars | Washer/operator assigned to the active wash |
| `updatedAt` | `timestamp` | required | Last state transition timestamp |

---

## 3. `/outlets/{outletId}/orders/{orderId}` (Transactions)

Customer intake transactions, payment records, wash lifecycle, and handover records.

| Field | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | `string` | `== orderId`, `1..80` chars | Document ID |
| `queueNumber` | `string` | `1..20` chars | Daily sequential ticket number (`'CW-001'`) |
| `outletId` | `string` | `== outletId` | Owning outlet document ID |
| `shiftId` | `string` | `1..80` chars | Active `ShiftSession` ID during order creation |
| `vehicleType` | `string` | `'mobil' \| 'motor'` | Vehicle category |
| `vehicleSize` | `string` | `'small' \| 'medium' \| 'large'` | Vehicle size tier |
| `brand` | `string` | `1..60` chars | Vehicle brand (`'Toyota'`, `'Honda'`, `'Yamaha'`, etc.) |
| `model` | `string` | `1..80` chars | Vehicle model (`'Innova Reborn'`, `'NMAX'`, `'HR-V'`) |
| `licensePlate` | `string` | `1..20` chars | Normalized uppercase plate (`'B 2841 SKZ'`) |
| `packageId` | `string` | `1..60` chars | Selected `WashPackage.id` |
| `packageName` | `string` | `1..80` chars | Snapshot of package display name |
| `price` | `int` | `1..10_000_000` | Package price in IDR (Rupiah) |
| `paymentMethod` | `string` | `'cash' \| 'qris'` | Selected payment channel |
| `paymentStatus` | `string` | `'pending' \| 'paid'` | Payment settlement status |
| `cashTendered` | `int` | `0..20_000_000` | Cash received from customer (`0` for QRIS / pay-later) |
| `changeAmount` | `int` | `0..20_000_000` | Cash change returned (`cashTendered - price` when paid) |
| `qrisProofFileName` | `string \| null` | `<= 255` chars | Optional attached QRIS proof filename |
| `status` | `string` | `'waiting' \| 'washing' \| 'ready' \| 'completed' \| 'cancelled'` | Workflow status |
| `bayId` | `string \| null` | `<= 40` chars | Assigned bay ID once washing begins |
| `bayName` | `string \| null` | `<= 60` chars | Assigned bay name snapshot |
| `operatorName` | `string \| null` | `<= 80` chars | Operator handling the wash |
| `pickupDisplay` | `string` | `1..60` chars | Customer-facing pickup estimate label (`'+1 Jam'`, `'Sore 17:30'`) |
| `estimatedReadyAt` | `timestamp` | required | Estimated ready timestamp |
| `startedWashingAt` | `timestamp \| null` | optional | Timestamp when vehicle entered bay |
| `finishedAt` | `timestamp \| null` | optional | Timestamp when wash finished (`ready`) |
| `completedAt` | `timestamp \| null` | optional | Timestamp when keys were handed over (`completed`) |
| `createdAt` | `timestamp` | required | Order creation timestamp |
| `dateKey` | `string` | `^\d{4}-\d{2}-\d{2}$` | Local operational date key (`'YYYY-MM-DD'`) |

---

## 4. `/outlets/{outletId}/shifts/{shiftId}`

Cashier shift lifecycle and end-of-shift cash drawer reconciliation.

| Field | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | `string` | `== shiftId`, `1..80` chars | Document ID |
| `cashierName` | `string` | `1..80` chars | Assigned cashier name |
| `terminalId` | `string` | `1..40` chars | POS terminal identifier (e.g., `'POS-SUNMI-01'`) |
| `bayLabel` | `string` | `1..60` chars | Outlet / bay group label |
| `shiftLabel` | `string` | `1..60` chars | Shift window label (e.g., `'Shift Pagi (08:00 - 16:00)'`) |
| `openedAt` | `timestamp` | required | Shift start timestamp |
| `closedAt` | `timestamp \| null` | optional | Shift close timestamp (`null` while `'open'`) |
| `openingCash` | `int` | `0..50_000_000` | Opening cash float in drawer (IDR) |
| `physicalCashCount` | `int` | `0..100_000_000` | Counted physical cash during audit/close (IDR) |
| `supervisorNotes` | `string` | `0..1000` chars | Handover or variance notes from cashier/supervisor |
| `status` | `string` | `'open' \| 'closed'` | Shift state (`'closed'` shifts are immutable) |

---

## 5. `/outlets/{outletId}/catalogs/{catalogId}`

Unified outlet catalog storing both wash pricing packages (`itemType == 'package'`) and vehicle brand/series presets (`itemType == 'vehicle_series'`) synced into the `O(1)` `MapCatalogRepository`.

| Field | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | `string` | `== catalogId`, `1..80` chars | Document ID (e.g., `'pkg_mobil_medium'`, `'vs_mobil_toyota_avanza'`) |
| `itemType` | `string` | `'package' \| 'vehicle_series'` | Discriminator between wash pricing packages and vehicle presets |
| `vehicleType` | `string` | `'mobil' \| 'motor'` | Vehicle category |
| `vehicleSize` | `string` | `'small' \| 'medium' \| 'large'` | Package tier size (`'package'`) or default recommended size (`'vehicle_series'`) |
| `brand` | `string \| null` | `1..60` chars for `'vehicle_series'`; `null` for `'package'` | Vehicle brand (`'Toyota'`, `'Honda'`, `'Yamaha'`) |
| `series` | `string \| null` | `1..80` chars for `'vehicle_series'`; `null` for `'package'` | Vehicle model/series (`'Avanza'`, `'Innova Reborn'`, `'NMAX'`) |
| `name` | `string \| null` | `1..80` chars for `'package'`; optional for `'vehicle_series'` | Wash package display title (`'Cuci Mobil Sedang'`) |
| `description` | `string \| null` | `<= 200` chars (optional) | Wash package size/tier helper text |
| `price` | `int \| null` | `1..10_000_000` for `'package'`; `null` or `0` for `'vehicle_series'` | Wash package price in IDR |
| `estimatedMinutes` | `int \| null` | `1..600` for `'package'`; `null` or `0` for `'vehicle_series'` | Estimated wash duration in minutes |
| `isActive` | `bool` | required | Soft-enable flag (`false` hides catalog entry without breaking order history) |
| `updatedAt` | `timestamp` (optional) | optional | Last catalog sync/edit timestamp |

---

## Atomic Transaction Strategy

All multi-document state transitions use `FirebaseFirestore.runTransaction(...)` with **all reads executed before writes** to guarantee strict consistency across concurrent handheld terminals:

### 1. Order Creation & Queue Sequencing (`createOrder`)
1. Locate the latest active shift reference prior to the transaction, then read both `_outletDoc` and `_shiftDoc` via `transaction.get(...)`.
2. Verify `shift.status == 'open'`.
3. Compute `nextSeq`: if `outlet.lastQueueDateKey == todayKey`, increment `lastQueueSeq + 1`; otherwise reset to `1`.
4. Format `queueNumber = 'CW-${nextSeq.padLeft(3, '0')}'`.
5. Update `_outletDoc` (`lastQueueDateKey`, `lastQueueSeq`, `updatedAt`) and insert `/orders/{orderId}` inside the same transaction.

### 2. Bay Allocation (`startWash`)
1. Read both `/orders/{orderId}` and `/bays/{bayId}` via `transaction.get(...)`.
2. Verify `order.status == 'waiting'`.
3. Verify `bay.status == 'available'` and `(bay.supportedType == null || bay.supportedType == order.vehicleType)`.
4. Atomically write:
   - Order: `status = 'washing'`, `bayId`, `bayName`, `operatorName`, `startedWashingAt = now`.
   - Bay: `status = 'occupied'`, `currentOrderId = order.id`, `currentPlate = order.licensePlate`, `operatorName`, `updatedAt = now`.
5. If two cashiers assign the same bay or same order concurrently, Firestore optimistic concurrency retries and the second transaction safely aborts with a `StateError`.

### 3. Wash Completion, Handover, & Cancellation
- **`markReadyForPickup`**: Reads `/orders/{orderId}` (and `/bays/{order.bayId}` if present). Verifies `order.status == 'washing'`, sets order `status = 'ready'` + `finishedAt = now`, and releases the bay (`status = 'available'`, `currentOrderId = null`, `currentPlate = null`, `operatorName = null`) only if `bay.currentOrderId == orderId`.
- **`completeHandover`**: Reads `/orders/{orderId}` (and `/bays/{order.bayId}` if still `washing`). Transitions order to `status = 'completed'`, `paymentStatus = 'paid'`, `completedAt = now` (setting `finishedAt` and releasing the bay if still `washing`).
- **`cancelOrder`**: Reads `/orders/{orderId}` (and `/bays/{order.bayId}` if `washing`). Rejects cancellation if already `'completed'` or `'cancelled'`; otherwise sets `status = 'cancelled'` and releases the occupied bay.

### 4. Shift Audit & Closing (`updateShiftAudit` / `closeShift`)
1. Locate the active shift reference, then read `/shifts/{shiftId}` inside `transaction.get(...)`.
2. Verify `shift.status == 'open'` (closed shifts cannot be overwritten, enforced both in transaction logic and `firestore.rules`).
3. For `updateShiftAudit`: persist draft `physicalCashCount` and `supervisorNotes`.
4. For `closeShift`: atomically set `physicalCashCount`, `supervisorNotes`, `closedAt = now`, and `status = 'closed'`.
5. Opening a subsequent shift (`reopenDemoShift`) creates a new `/shifts/{newShiftId}` document with `status = 'open'`, preserving closed shift history intact.

---

## Primary Query Patterns & Indexes

| Query | Filter / Sort | Supporting Index |
| :--- | :--- | :--- |
| Daily orders feed | `where('dateKey', isEqualTo: today)` + `orderBy('createdAt', descending: true)` | `orders`: `dateKey` ASC, `createdAt` DESC |
| Queue lane filter | `where('status', isEqualTo: status)` + `orderBy('createdAt', descending: false)` | `orders`: `status` ASC, `createdAt` ASC |
| Shift revenue report | `where('shiftId', isEqualTo: shiftId)` + `orderBy('createdAt', descending: true)` | `orders`: `shiftId` ASC, `createdAt` DESC |
| Active / latest shift | `orderBy('openedAt', descending: true).limit(1)` | `shifts`: `openedAt` DESC (`status` ASC + `openedAt` DESC for filtered active queries) |
| Active outlet catalog | `where('vehicleType', isEqualTo: type)` + `where('isActive', isEqualTo: true)` | `catalogs`: `vehicleType` ASC, `isActive` ASC |
