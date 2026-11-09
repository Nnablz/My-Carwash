# ClearWash - Carwash Mobile POS & Queue Management System

A high-performance, industrial-grade mobile Point-of-Sale (POS) and bay queue tracking application built with Flutter, Riverpod (Dependency Injection & State Management), and Cloud Firestore.

Designed for handheld terminals (Sunmi, iMin) and ruggedized Android smartphones operated in high-pace carwash and detailing bays.

---

## Design System & Stitch MCP Specification

The user interface and operational flows are engineered from the Carwash Mobile POS UI (`projects/16690515153313102737` in Google Stitch).

- **Design Philosophy**: Industrial Utility & Functional Ergonomics
  - **High Contrast**: Optimized for wet-floor environments and direct midday sunlight.
  - **Large Touch Targets**: 100% thumb-zone accessibility (minimum 58px button height) for single-handed use or gloved operation.
  - **Machine-Readable Typography**: Space Grotesk for UI labels and JetBrains Mono for license plates (Plat Nomor), transaction IDs, and currency (Rp).

---

## Upcoming Features Roadmap (From Stitch Designs)

Based on the interactive screens designed in Stitch, the following core operational modules are being rolled out:

### 1. Kendaraan Intake & Registrasi (Check-In & Registration)
- **Vehicle Type Selector**: One-tap toggles between Mobil (Car) and Motor (Motorcycle).
- **Brand & Model Database**: Quick dropdown and autocomplete for common brands (Toyota, Honda, Mitsubishi, Daihatsu, Yamaha, Suzuki, Vespa, etc.).
- **License Plate Badge (Plat Nomor)**: High-visibility Indonesian license plate input and formatting (B 1234 ABC).
- **Vehicle Size & Package Tiering**:
  - Mobil Kecil (< 1.200cc: City Car / Compact)
  - Mobil Sedang (1.200cc - 2.000cc: MPV / Sedan)
  - Mobil Besar (> 2.000cc: Large SUV / Van)
  - Motor Kecil / Sedang / Besar (Moge)
- **Estimated Completion / Siap Ambil**: Preset time selector (+1 Jam, Sore 17:30, Malam 19:00, or Sesuai Antrian).

### 2. Multi-Channel Payment & Ticket Printing
- **Dual Payment Methods**:
  - **Tunai (Cash)**: Cash tendered with instant change calculation.
  - **QRIS Dinamis**: In-app QRIS generation with live payment status listener and photo proof attachment (Foto Bukti Pembayaran).
- **Thermal Receipt & Bay Ticket**: Direct ESC/POS printing for customer queue tickets and dashboard entry slips.

### 3. Antrian Lapangan (Real-time Bay & Queue Tracking)
- **Live Queue Lane View**: Filterable by status (Semua, Menunggu, Dicuci, Selesai).
- **Bay Allocation & Active Timers**: Visual slots (Bay 01, Bay 02, etc.) with real-time countdown timers.
- **Workflow State Transitions**:
  - Menunggu -> Mulai Cuci (Masuk Bay) -> Selesai Cuci (Ke Finishing) -> Serahkan Kunci / Selesai.
- **Operational Metrics Bar**: Average wash duration, occupied bay slots, and daily completed vehicle volume.

### 4. Ringkasan Shift & Rekonsiliasi Kas (Shift End & Cash Reconciliation)
- **Shift Performance Summary**: Gross shift revenue, target delta (+14% vs target), and transaction counts.
- **Payment Breakdown**: Real-time cash vs. QRIS/non-cash reconciliation.
- **Volume & Category Analytics**: Proportion of cars vs. motorcycles and vehicle size distributions.
- **Cash Drawer Audit (Laci Kas)**: System recorded vs. counted physical cash with automatic variance calculation (Selisih: Rp 0 - Balance).
- **Supervisor Handover Notes & Shift Closing Report**: Printable end-of-shift handover report sent to management.

---

## Current Project Architecture

The base project has been configured with clean, scalable architecture:

```text
lib/
|-- di/
|   `-- providers.dart         # Riverpod Dependency Injection container & StreamProviders
|-- firebase/
|   `-- firebase_options.dart  # Multi-environment Firebase configurations
|-- models/
|   `-- protein_entry.dart     # Reactive domain models
|-- repositories/
|   `-- protein_repository.dart# Repository contracts with Firestore & InMemory fallback
|-- screens/
|   `-- home_screen.dart       # Reactive ConsumerWidget with Material 3
`-- main.dart                  # App bootstrap wrapped with ProviderScope
```

---

## Getting Started

### Prerequisites
- Flutter SDK ^3.12.0 (Dart 3.x)
- Android SDK / Android Studio (Targeting minSdk 23)

### Installation
```bash
# Clone the repository
git clone https://github.com/Nnablz/My-Carwash.git

# Install dependencies
flutter pub get

# Run static analysis
flutter analyze

# Run unit and widget tests
flutter test

# Launch debug app on connected device / emulator
flutter run
```

---

## License
This project is open-source and available under the [MIT License](LICENSE).
