#!/usr/bin/env node

/**
 * Build Info for BarcodeScanner
 * Generated: May 11, 2026
 */

const buildInfo = {
  projectName: 'BarcodeScanner',
  version: '1.0.0',
  builtAt: new Date('2026-05-11'),
  
  structure: {
    documentation: 8,        // README files
    typescript: 5,           // .ts/.tsx files
    swift: 4,                // .swift files
    configuration: 6,        // config files
  },
  
  packages: {
    expo: '55.0.23',
    react: '19.2.6',
    'react-native': '0.85.3',
    'expo-camera': '55.0.18',
  },
  
  features: {
    temporalSmoothing: true,
    nativeModules: true,
    typescriptSupport: true,
    iosSupport: true,
    androidSupport: true,
    tfliteReady: false,        // Need integration
    visionApiReady: false,     // Need integration
  },
  
  requirements: {
    nodeVersion: '18.0.0',
    iosVersion: '14.0',
    xcode: '15.0',
  },
};

console.log('🎉 BarcodeScanner Build Info');
console.log('=============================');
console.log(`Version: ${buildInfo.version}`);
console.log(`Built: ${buildInfo.builtAt.toISOString().split('T')[0]}`);
console.log('');
console.log('📊 Project Statistics:');
console.log(`  • Documentation files: ${buildInfo.structure.documentation}`);
console.log(`  • TypeScript files: ${buildInfo.structure.typescript}`);
console.log(`  • Swift files: ${buildInfo.structure.swift}`);
console.log(`  • Configuration files: ${buildInfo.structure.configuration}`);
console.log('');
console.log('✅ Features Ready:');
buildInfo.features.temporalSmoothing && console.log('  ✓ Temporal Smoothing');
buildInfo.features.nativeModules && console.log('  ✓ Native Modules');
buildInfo.features.typescriptSupport && console.log('  ✓ TypeScript Support');
buildInfo.features.iosSupport && console.log('  ✓ iOS Support');
buildInfo.features.androidSupport && console.log('  ✓ Android Support');
console.log('');
console.log('⏳ Need Integration:');
!buildInfo.features.tfliteReady && console.log('  ⏳ TFLite Support (see INTEGRATION_GUIDE.md)');
!buildInfo.features.visionApiReady && console.log('  ⏳ Vision API Support (see INTEGRATION_GUIDE.md)');
console.log('');
console.log('🚀 Next Steps:');
console.log('  1. npm install');
console.log('  2. npm start');
console.log('  3. Press "i" for iOS');
console.log('');

module.exports = buildInfo;
