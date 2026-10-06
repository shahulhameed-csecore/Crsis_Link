# Nearby Connections Constraints

- The project uses `nearby_connections: ^4.3.0`.
- **Do not** use `Nearby().checkLocationEnabled()` to check if GPS is turned on. This method does not exist in version 4.3.0 and will cause a `compileFlutterBuildRelease` error.
- **Instead**, use `Geolocator.isLocationServiceEnabled()` from the `geolocator` package.
