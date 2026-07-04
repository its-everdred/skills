const fs = require('fs');
const path = require('path');

// Read the build.gradle file
const buildGradlePath = path.join(__dirname, '../android/app/build.gradle');
let buildGradle = fs.readFileSync(buildGradlePath, 'utf8');

// Check if release signing config exists
const hasReleaseSigningConfig = buildGradle.includes('signingConfigs') &&
                                buildGradle.includes('release {') &&
                                buildGradle.includes('keyAlias project.properties.get("MYAPP_UPLOAD_KEY_ALIAS")');

if (!hasReleaseSigningConfig) {
  // Add release signing config to signingConfigs section
  const signingConfigsRegex = /(signingConfigs\s*{\s*debug\s*{[^}]+}\s*)(})/;
  const releaseSigningConfig = `        release {
            storeFile file(project.properties.get("MYAPP_UPLOAD_STORE_FILE"))
            storePassword System.getenv("ANDROID_UPLOAD_STORE_PASSWORD")
            keyAlias project.properties.get("MYAPP_UPLOAD_KEY_ALIAS")
            keyPassword System.getenv("ANDROID_UPLOAD_KEY_PASSWORD")
        }
    `;

  buildGradle = buildGradle.replace(signingConfigsRegex, `$1${releaseSigningConfig}}`);
  console.log('✓ Added release signing configuration');
}

// Now update the release buildType to use release signing config instead of debug
const releaseRegex = /(release\s*{\s*\/\/.*\n\s*\/\/.*\n\s*signingConfig\s+signingConfigs\.)debug/m;
if (releaseRegex.test(buildGradle)) {
  buildGradle = buildGradle.replace(releaseRegex, '$1release');
  console.log('✓ Updated release build to use release signing');
}

// Write the updated file
fs.writeFileSync(buildGradlePath, buildGradle);
console.log('✓ Android signing configuration complete');
