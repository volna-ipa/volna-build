# Generates a classic Xcode project (objectVersion 56) without XcodeGen.
# Usage: powershell -ExecutionPolicy Bypass -File tools/generate-xcodeproj.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$projectDir = Join-Path $root 'Volna.xcodeproj'
$sourceRoot = Join-Path $root 'Volna'
New-Item -ItemType Directory -Force -Path $projectDir | Out-Null

function New-StableId {
    param([string]$Key)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Key))
    return (($hash | ForEach-Object { $_.ToString('X2') }) -join '').Substring(0, 24)
}

function Relative-Path {
    param([string]$Path)
    return $Path.Substring($sourceRoot.Length).TrimStart('\', '/') -replace '\\', '/'
}

$swiftFiles = Get-ChildItem -Path $sourceRoot -Filter '*.swift' -Recurse | Sort-Object FullName
$fileRefs = @{}
$buildFiles = @{}
foreach ($file in $swiftFiles) {
    $rel = Relative-Path $file.FullName
    $fileRefs[$rel] = New-StableId "fileref:$rel"
    $buildFiles[$rel] = New-StableId "buildfile:$rel"
}

$groupIds = @{
    root = New-StableId 'group:root'
    app = New-StableId 'group:app'
    core = New-StableId 'group:core'
    api = New-StableId 'group:api'
    models = New-StableId 'group:models'
    recs = New-StableId 'group:recommendations'
    library = New-StableId 'group:library'
    player = New-StableId 'group:player'
    utilities = New-StableId 'group:utilities'
    design = New-StableId 'group:design'
    features = New-StableId 'group:features'
    onboarding = New-StableId 'group:onboarding'
    feed = New-StableId 'group:feed'
    search = New-StableId 'group:search'
    libFeature = New-StableId 'group:library-feature'
    playerFeature = New-StableId 'group:player-feature'
    settings = New-StableId 'group:settings'
    web = New-StableId 'group:web'
    resources = New-StableId 'group:resources'
    config = New-StableId 'group:config'
    products = New-StableId 'group:products'
}

$targetId = New-StableId 'target:volna'
$projectId = New-StableId 'project:volna'
$productId = New-StableId 'product:volna'
$mainGroupId = New-StableId 'group:main'
$sourcesPhaseId = New-StableId 'phase:sources'
$frameworksPhaseId = New-StableId 'phase:frameworks'
$resourcesPhaseId = New-StableId 'phase:resources'
$projectConfigListId = New-StableId 'configlist:project'
$targetConfigListId = New-StableId 'configlist:target'
$projectDebugId = New-StableId 'config:project:debug'
$projectReleaseId = New-StableId 'config:project:release'
$targetDebugId = New-StableId 'config:target:debug'
$targetReleaseId = New-StableId 'config:target:release'
$appConfigRefId = New-StableId 'fileref:Config/App.xcconfig'
$secretsConfigRefId = New-StableId 'fileref:Config/Secrets.xcconfig'
$infoPlistRefId = New-StableId 'fileref:Config/Info.plist'
$assetsRefId = New-StableId 'fileref:Resources/Assets.xcassets'
$privacyRefId = New-StableId 'fileref:Resources/PrivacyInfo.xcprivacy'
$assetsBuildId = New-StableId 'buildfile:Resources/Assets.xcassets'
$privacyBuildId = New-StableId 'buildfile:Resources/PrivacyInfo.xcprivacy'

function File-Ref {
    param([string]$Id, [string]$Path, [string]$Type)
    return "`t`t$Id /* $Path */ = {isa = PBXFileReference; lastKnownFileType = $Type; path = `"$Path`"; sourceTree = `"<group>`"; };"
}

function Build-File {
    param([string]$Id, [string]$FileRef, [string]$Name)
    return "`t`t$Id /* $Name in Sources */ = {isa = PBXBuildFile; fileRef = $FileRef /* $Name */; };"
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('// !$*UTF8*$!')
$lines.Add('{')
$lines.Add('	archiveVersion = 1;')
$lines.Add('	classes = {')
$lines.Add('	};')
$lines.Add('	objectVersion = 56;')
$lines.Add('	objects = {')

# PBXBuildFile
$lines.Add('')
$lines.Add('/* Begin PBXBuildFile section */')
foreach ($file in $swiftFiles) {
    $rel = Relative-Path $file.FullName
    $name = $file.Name
    $lines.Add((Build-File $buildFiles[$rel] $fileRefs[$rel] $name))
}
$lines.Add("`t`t$assetsBuildId /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = $assetsRefId /* Assets.xcassets */; };")
$lines.Add("`t`t$privacyBuildId /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = $privacyRefId /* PrivacyInfo.xcprivacy */; };")
$lines.Add('/* End PBXBuildFile section */')

# PBXFileReference
$lines.Add('')
$lines.Add('/* Begin PBXFileReference section */')
foreach ($file in $swiftFiles) {
    $rel = Relative-Path $file.FullName
    $lines.Add((File-Ref $fileRefs[$rel] $file.Name 'sourcecode.swift'))
}
$lines.Add("`t`t$productId /* Volna.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Volna.app; sourceTree = BUILT_PRODUCTS_DIR; };")
$lines.Add((File-Ref $appConfigRefId 'App.xcconfig' 'text.xcconfig'))
$lines.Add((File-Ref $secretsConfigRefId 'Secrets.xcconfig' 'text.xcconfig'))
$lines.Add((File-Ref $infoPlistRefId 'Info.plist' 'text.plist.xml'))
$lines.Add((File-Ref $assetsRefId 'Assets.xcassets' 'folder.assetcatalog'))
$lines.Add((File-Ref $privacyRefId 'PrivacyInfo.xcprivacy' 'text.xml'))
$lines.Add('/* End PBXFileReference section */')

# Groups
$lines.Add('')
$lines.Add('/* Begin PBXGroup section */')

function Emit-Group {
    param([string]$Id, [string]$Name, [string]$Path, [string[]]$Children, [bool]$IsRoot = $false)
    $pathPart = if ($Path) { "path = `"$Path`"; " } else { '' }
    $lines.Add("`t`t$Id /* $Name */ = {")
    $lines.Add('			isa = PBXGroup;')
    $lines.Add("			children = (")
    foreach ($child in $Children) {
        $lines.Add("				$child,")
    }
    $lines.Add('			);')
    $lines.Add("			$($pathPart)sourceTree = `"<group>`";")
    $lines.Add('		};')
}

$appChildren = @($fileRefs['App/VolnaApp.swift'], $fileRefs['App/AppEnvironment.swift'], $fileRefs['App/RootView.swift'])
$coreChildren = @(
    $groupIds.api, $groupIds.models, $groupIds.recs, $groupIds.library,
    $groupIds.player, $groupIds.utilities
)
$designChildren = @(
    $fileRefs['DesignSystem/ArtworkView.swift'], $fileRefs['DesignSystem/Theme.swift'],
    $fileRefs['DesignSystem/Components.swift']
)
$featuresChildren = @(
    $groupIds.onboarding, $groupIds.feed, $groupIds.search, $groupIds.libFeature,
    $groupIds.playerFeature, $groupIds.settings, $groupIds.web
)
$resourcesChildren = @($assetsRefId, $privacyRefId)
$rootSourceChildren = @($groupIds.app, $groupIds.core, $groupIds.design, $groupIds.features, $groupIds.resources)
$mainChildren = @($groupIds.root, $groupIds.config, $groupIds.products)

Emit-Group $mainGroupId 'Main' '' $mainChildren $true
Emit-Group $groupIds.root 'Volna' 'Volna' $rootSourceChildren
Emit-Group $groupIds.app 'App' 'App' $appChildren
Emit-Group $groupIds.core 'Core' 'Core' $coreChildren
Emit-Group $groupIds.api 'API' 'API' @(
    $fileRefs['Core/API/APIError.swift'], $fileRefs['Core/API/AppConfiguration.swift'],
    $fileRefs['Core/API/CredentialsStore.swift'], $fileRefs['Core/API/KeychainStore.swift'],
    $fileRefs['Core/API/RateLimiter.swift'], $fileRefs['Core/API/SoundCloudAPIClient.swift'],
    $fileRefs['Core/API/SoundCloudAuthService.swift']
)
Emit-Group $groupIds.models 'Models' 'Models' @(
    $fileRefs['Core/Models/Models.swift'], $fileRefs['Core/Models/SoundCloudDTO.swift']
)
Emit-Group $groupIds.recs 'Recommendations' 'Recommendations' @(
    $fileRefs['Core/Recommendations/FeedCache.swift'], $fileRefs['Core/Recommendations/FeedViewModel.swift'],
    $fileRefs['Core/Recommendations/RecommendationEngine.swift']
)
Emit-Group $groupIds.library 'Library' 'Library' @(
    $fileRefs['Core/Library/ArtworkCache.swift'], $fileRefs['Core/Library/LibraryStore.swift'],
    $fileRefs['Core/Library/PersistenceController.swift']
)
Emit-Group $groupIds.player 'Player' 'Player' @(
    $fileRefs['Core/Player/NowPlayingController.swift'], $fileRefs['Core/Player/PlaybackController.swift']
)
Emit-Group $groupIds.utilities 'Utilities' 'Utilities' @(
    $fileRefs['Core/Utilities/AppSettings.swift'], $fileRefs['Core/Utilities/Formatters.swift']
)
Emit-Group $groupIds.design 'DesignSystem' 'DesignSystem' $designChildren
Emit-Group $groupIds.features 'Features' 'Features' $featuresChildren
Emit-Group $groupIds.onboarding 'Onboarding' 'Onboarding' @($fileRefs['Features/Onboarding/OnboardingView.swift'])
Emit-Group $groupIds.feed 'Feed' 'Feed' @(
    $fileRefs['Features/Feed/HomeView.swift'], $fileRefs['Features/Feed/MixDetailView.swift']
)
Emit-Group $groupIds.search 'Search' 'Search' @($fileRefs['Features/Search/SearchView.swift'])
Emit-Group $groupIds.libFeature 'Library' 'Library' @(
    $fileRefs['Features/Library/LibraryView.swift'], $fileRefs['Features/Library/PlaylistDetailView.swift']
)
Emit-Group $groupIds.playerFeature 'Player' 'Player' @(
    $fileRefs['Features/Player/PlayerView.swift'], $fileRefs['Features/Player/QueueView.swift']
)
Emit-Group $groupIds.settings 'Settings' 'Settings' @(
    $fileRefs['Features/Settings/SettingsView.swift'], $fileRefs['Features/Settings/TasteEditorView.swift']
)
Emit-Group $groupIds.web 'WebFallback' 'WebFallback' @($fileRefs['Features/WebFallback/WebFallbackView.swift'])
Emit-Group $groupIds.resources 'Resources' 'Resources' $resourcesChildren
Emit-Group $groupIds.config 'Config' 'Config' @($appConfigRefId, $secretsConfigRefId, $infoPlistRefId)
Emit-Group $groupIds.products 'Products' '' @($productId)
$lines.Add('/* End PBXGroup section */')

# Native target
$lines.Add('')
$lines.Add('/* Begin PBXNativeTarget section */')
$lines.Add("`t`t$targetId /* Volna */ = {")
$lines.Add('			isa = PBXNativeTarget;')
$lines.Add("			buildConfigurationList = $targetConfigListId /* Build configuration list for PBXNativeTarget `"Volna`" */;")
$lines.Add('			buildPhases = (')
$lines.Add("				$sourcesPhaseId /* Sources */,")
$lines.Add("				$frameworksPhaseId /* Frameworks */,")
$lines.Add("				$resourcesPhaseId /* Resources */,")
$lines.Add('			);')
$lines.Add('			buildRules = (')
$lines.Add('			);')
$lines.Add('			dependencies = (')
$lines.Add('			);')
$lines.Add('			name = Volna;')
$lines.Add('			productName = Volna;')
$lines.Add("			productReference = $productId /* Volna.app */;")
$lines.Add('			productType = "com.apple.product-type.application";')
$lines.Add('		};')
$lines.Add('/* End PBXNativeTarget section */')

# Project
$lines.Add('')
$lines.Add('/* Begin PBXProject section */')
$lines.Add("`t`t$projectId /* Project object */ = {")
$lines.Add('			isa = PBXProject;')
$lines.Add('			attributes = {')
$lines.Add('				BuildIndependentTargetsInParallel = 1;')
$lines.Add('				LastSwiftUpdateCheck = 1600;')
$lines.Add('				LastUpgradeCheck = 1600;')
$lines.Add('				TargetAttributes = {')
$lines.Add("					$targetId = {")
$lines.Add('						CreatedOnToolsVersion = 16.0;')
$lines.Add('					};')
$lines.Add('				};')
$lines.Add('			};')
$lines.Add("			buildConfigurationList = $projectConfigListId /* Build configuration list for PBXProject `"Volna`" */;")
$lines.Add('			compatibilityVersion = "Xcode 14.0";')
$lines.Add('			developmentRegion = ru;')
$lines.Add('			hasScannedForEncodings = 0;')
$lines.Add('			knownRegions = (')
$lines.Add('				ru,')
$lines.Add('				en,')
$lines.Add('				Base,')
$lines.Add('			);')
$lines.Add("			mainGroup = $mainGroupId;")
$lines.Add("			productRefGroup = $($groupIds.products) /* Products */;")
$lines.Add('			projectDirPath = "";')
$lines.Add('			projectRoot = "";')
$lines.Add('			targets = (')
$lines.Add("				$targetId /* Volna */,")
$lines.Add('			);')
$lines.Add('		};')
$lines.Add('/* End PBXProject section */')

# Build phases
$lines.Add('')
$lines.Add('/* Begin PBXResourcesBuildPhase section */')
$lines.Add("`t`t$resourcesPhaseId /* Resources */ = {")
$lines.Add('			isa = PBXResourcesBuildPhase;')
$lines.Add('			buildActionMask = 2147483647;')
$lines.Add('			files = (')
$lines.Add("				$assetsBuildId /* Assets.xcassets in Resources */,")
$lines.Add("				$privacyBuildId /* PrivacyInfo.xcprivacy in Resources */,")
$lines.Add('			);')
$lines.Add('			runOnlyForDeploymentPostprocessing = 0;')
$lines.Add('		};')
$lines.Add('/* End PBXResourcesBuildPhase section */')

$lines.Add('')
$lines.Add('/* Begin PBXSourcesBuildPhase section */')
$lines.Add("`t`t$sourcesPhaseId /* Sources */ = {")
$lines.Add('			isa = PBXSourcesBuildPhase;')
$lines.Add('			buildActionMask = 2147483647;')
$lines.Add('			files = (')
foreach ($file in $swiftFiles) {
    $rel = Relative-Path $file.FullName
    $lines.Add("				$($buildFiles[$rel]) /* $($file.Name) in Sources */,")
}
$lines.Add('			);')
$lines.Add('			runOnlyForDeploymentPostprocessing = 0;')
$lines.Add('		};')
$lines.Add('/* End PBXSourcesBuildPhase section */')

$lines.Add('')
$lines.Add('/* Begin PBXFrameworksBuildPhase section */')
$lines.Add("`t`t$frameworksPhaseId /* Frameworks */ = {")
$lines.Add('			isa = PBXFrameworksBuildPhase;')
$lines.Add('			buildActionMask = 2147483647;')
$lines.Add('			files = (')
$lines.Add('			);')
$lines.Add('			runOnlyForDeploymentPostprocessing = 0;')
$lines.Add('		};')
$lines.Add('/* End PBXFrameworksBuildPhase section */')

# Build configurations
function Emit-Config {
    param([string]$Id, [string]$Name, [string[]]$Settings, [string]$BaseConfigRef = '')
    $lines.Add("`t`t$Id /* $Name */ = {")
    $lines.Add('			isa = XCBuildConfiguration;')
    if ($BaseConfigRef) {
        $lines.Add("			baseConfigurationReference = $BaseConfigRef;")
    }
    $lines.Add('			buildSettings = {')
    foreach ($setting in $Settings) { $lines.Add("				$setting") }
    $lines.Add('			};')
    $lines.Add("			name = $Name;")
    $lines.Add('		};')
}

$projectCommon = @(
    'ALWAYS_SEARCH_USER_PATHS = NO;',
    'CLANG_ANALYZER_NONNULL = YES;',
    'CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";',
    'CLANG_ENABLE_MODULES = YES;',
    'CLANG_ENABLE_OBJC_ARC = YES;',
    'CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;',
    'CLANG_WARN_BOOL_CONVERSION = YES;',
    'CLANG_WARN_COMMA = YES;',
    'CLANG_WARN_CONSTANT_CONVERSION = YES;',
    'CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;',
    'CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;',
    'CLANG_WARN_DOCUMENTATION_COMMENTS = YES;',
    'CLANG_WARN_EMPTY_BODY = YES;',
    'CLANG_WARN_ENUM_CONVERSION = YES;',
    'CLANG_WARN_INFINITE_RECURSION = YES;',
    'CLANG_WARN_INT_CONVERSION = YES;',
    'CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;',
    'CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;',
    'CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;',
    'CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;',
    'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;',
    'CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;',
    'CLANG_WARN_STRICT_PROTOTYPES = YES;',
    'CLANG_WARN_SUSPICIOUS_MOVE = YES;',
    'CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;',
    'CLANG_WARN_UNREACHABLE_CODE = YES;',
    'CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;',
    'COPY_PHASE_STRIP = NO;',
    'ENABLE_STRICT_OBJC_MSGSEND = YES;',
    'GCC_C_LANGUAGE_STANDARD = gnu17;',
    'GCC_NO_COMMON_BLOCKS = YES;',
    'GCC_WARN_64_TO_32_BIT_CONVERSION = YES;',
    'GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;',
    'GCC_WARN_UNDECLARED_SELECTOR = YES;',
    'GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;',
    'GCC_WARN_UNUSED_FUNCTION = YES;',
    'GCC_WARN_UNUSED_VARIABLE = YES;',
    'IPHONEOS_DEPLOYMENT_TARGET = 16.0;',
    'LOCALIZATION_PREFERS_STRING_CATALOGS = YES;',
    'MTL_FAST_MATH = YES;',
    'SDKROOT = iphoneos;',
    'SWIFT_STRICT_CONCURRENCY = minimal;'
)
$projectDebug = $projectCommon + @(
    'DEBUG_INFORMATION_FORMAT = dwarf;',
    'ENABLE_TESTABILITY = YES;',
    'GCC_OPTIMIZATION_LEVEL = 0;',
    'GCC_PREPROCESSOR_DEFINITIONS = (',
    '    "DEBUG=1",',
    '    "$(inherited)",',
    ');',
    'MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;',
    'ONLY_ACTIVE_ARCH = YES;',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";',
    'SWIFT_OPTIMIZATION_LEVEL = "-Onone";'
)
$projectRelease = $projectCommon + @(
    'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
    'ENABLE_NS_ASSERTIONS = NO;',
    'MTL_ENABLE_DEBUG_INFO = NO;',
    'SWIFT_COMPILATION_MODE = wholemodule;',
    'SWIFT_OPTIMIZATION_LEVEL = "-O";',
    'VALIDATE_PRODUCT = YES;'
)

$targetCommon = @(
    'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;',
    'CODE_SIGN_STYLE = Automatic;',
    'CURRENT_PROJECT_VERSION = 1;',
    'DEVELOPMENT_TEAM = "";',
    'ENABLE_PREVIEWS = YES;',
    'GENERATE_INFOPLIST_FILE = NO;',
    'INFOPLIST_FILE = Config/Info.plist;',
    'LD_RUNPATH_SEARCH_PATHS = (',
    '    "$(inherited)",',
    '    "@executable_path/Frameworks",',
    ');',
    'MARKETING_VERSION = 1.0;',
    'PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_ID)";',
    'PRODUCT_NAME = "$(TARGET_NAME)";',
    'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";',
    'SUPPORTS_MACCATALYST = NO;',
    'SWIFT_EMIT_LOC_STRINGS = YES;',
    'SWIFT_VERSION = 5.0;',
    'TARGETED_DEVICE_FAMILY = 1;'
)

$lines.Add('')
$lines.Add('/* Begin XCBuildConfiguration section */')
Emit-Config $projectDebugId 'Debug' $projectDebug
Emit-Config $projectReleaseId 'Release' $projectRelease
Emit-Config $targetDebugId 'Debug' $targetCommon "$appConfigRefId /* App.xcconfig */"
Emit-Config $targetReleaseId 'Release' $targetCommon "$appConfigRefId /* App.xcconfig */"
$lines.Add('/* End XCBuildConfiguration section */')

# Config lists
$lines.Add('')
$lines.Add('/* Begin XCConfigurationList section */')
$lines.Add("`t`t$projectConfigListId /* Build configuration list for PBXProject `"Volna`" */ = {")
$lines.Add('			isa = XCConfigurationList;')
$lines.Add('			buildConfigurations = (')
$lines.Add("				$projectDebugId /* Debug */,")
$lines.Add("				$projectReleaseId /* Release */,")
$lines.Add('			);')
$lines.Add('			defaultConfigurationIsVisible = 0;')
$lines.Add('			defaultConfigurationName = Release;')
$lines.Add('		};')
$lines.Add("`t`t$targetConfigListId /* Build configuration list for PBXNativeTarget `"Volna`" */ = {")
$lines.Add('			isa = XCConfigurationList;')
$lines.Add('			buildConfigurations = (')
$lines.Add("				$targetDebugId /* Debug */,")
$lines.Add("				$targetReleaseId /* Release */,")
$lines.Add('			);')
$lines.Add('			defaultConfigurationIsVisible = 0;')
$lines.Add('			defaultConfigurationName = Release;')
$lines.Add('		};')
$lines.Add('/* End XCConfigurationList section */')

$lines.Add('	};')
$lines.Add("	rootObject = $projectId /* Project object */;")
$lines.Add('}')

$content = $lines -join "`r`n"
# Guard against PowerShell object names leaking into the file through a bad
# string interpolation (e.g. "$hash.key" instead of "$($hash.key)").
if ($content -match 'System\.Collections') {
    throw 'project.pbxproj contains a rendered PowerShell object; check string interpolation in the generator.'
}
# Xcode rejects project.pbxproj files that start with a UTF-8 BOM, so write it without one.
[IO.File]::WriteAllText((Join-Path $projectDir 'project.pbxproj'), $content, (New-Object System.Text.UTF8Encoding($false)))

# Shared scheme
$schemeDir = Join-Path $projectDir 'xcshareddata\xcschemes'
New-Item -ItemType Directory -Force -Path $schemeDir | Out-Null
$scheme = @"
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "$targetId"
               BuildableName = "Volna.app"
               BlueprintName = "Volna"
               ReferencedContainer = "container:Volna.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "$targetId"
            BuildableName = "Volna.app"
            BlueprintName = "Volna"
            ReferencedContainer = "container:Volna.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "$targetId"
            BuildableName = "Volna.app"
            BlueprintName = "Volna"
            ReferencedContainer = "container:Volna.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"@
Set-Content -LiteralPath (Join-Path $schemeDir 'Volna.xcscheme') -Value $scheme -Encoding UTF8
# Normalize the scheme to UTF-8 without BOM as well (harmless for XML, consistent with the pbxproj).
[IO.File]::WriteAllText((Join-Path $schemeDir 'Volna.xcscheme'), (Get-Content -LiteralPath (Join-Path $schemeDir 'Volna.xcscheme') -Raw), (New-Object System.Text.UTF8Encoding($false)))

Write-Output "Generated $projectDir"
Write-Output "Swift files: $($swiftFiles.Count)"
