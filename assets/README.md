# Assets Folder Structure

This folder contains all the static assets used in the Telnyx Flutter Demo app.

## Folder Structure

```
assets/
├── images/
│   ├── logos/          # Company logos, app logos, brand assets
│   ├── icons/          # UI icons, button icons, status icons
│   └── backgrounds/    # Background images, patterns, textures
├── fonts/              # Custom fonts (if any)
├── audio/              # Sound effects, notification sounds
└── README.md          # This file
```

## Usage in Flutter

### Images
To use images in your Flutter app, reference them like this:

```dart
// For logos
Image.asset('assets/images/logos/telnyx_logo.png')

// For icons
Image.asset('assets/images/icons/call_icon.png')

// For backgrounds
Container(
  decoration: BoxDecoration(
    image: DecorationImage(
      image: AssetImage('assets/images/backgrounds/call_bg.jpg'),
      fit: BoxFit.cover,
    ),
  ),
)
```

### Audio
For audio files:

```dart
// Using just_audio package
AudioPlayer audioPlayer = AudioPlayer();
await audioPlayer.setAsset('assets/audio/ringtone.mp3');
```

## File Naming Conventions

- Use lowercase with underscores: `telnyx_logo.png`
- Be descriptive: `incoming_call_icon.png` instead of `icon1.png`
- Include size variants: `logo_32x32.png`, `logo_64x64.png`
- Use appropriate formats:
  - PNG for images with transparency
  - JPG for photos/backgrounds
  - SVG for scalable vector graphics (convert to PNG for Flutter)
  - MP3 for audio files

## Adding New Assets

1. Place your asset in the appropriate subfolder
2. Run `flutter pub get` to refresh the asset bundle
3. Reference the asset using the path relative to the `assets/` folder

## Asset Optimization

- Compress images before adding them to reduce app size
- Use appropriate image sizes for different screen densities
- Consider using vector graphics (SVG converted to PNG) for scalability
