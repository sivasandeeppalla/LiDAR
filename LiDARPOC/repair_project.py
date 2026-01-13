import os
import uuid

def generate_id():
    return uuid.uuid4().hex[:24].upper()

project_path = "/Users/sivasandeep/Documents/GitHub/LiDAR/LiDARPOC/LiDARPOC.xcodeproj/project.pbxproj"

# Known IDs from existing project
TARGET_ID = "8552E4612EED38750063C5D8"
SOURCES_BUILD_PHASE_ID = "8552E45E2EED38750063C5D8"
RESOURCES_BUILD_PHASE_ID = "8552E4602EED38750063C5D8"
FRAMEWORKS_BUILD_PHASE_ID = "8552E45F2EED38750063C5D8"
MAIN_GROUP_ID = "8552E4592EED38750063C5D8"
LIDARPOC_GROUP_ID = "8552E4642EED38750063C5D8"
PRODUCTS_GROUP_ID = "8552E4632EED38750063C5D8"
APP_FILE_REF_ID = "8552E4622EED38750063C5D8"
PROJECT_OBJ_ID = "8552E45A2EED38750063C5D8"
PROJECT_CONFIG_LIST_ID = "8552E45D2EED38750063C5D8"
TARGET_CONFIG_LIST_ID = "8552E4702EED38770063C5D8"

# Files to add
# Format: (Filename, Type, IsResource?, Subfolder)
files = [
    ("APIService.swift", "sourcecode.swift", False, None),
    ("CameraRecordView.swift", "sourcecode.swift", False, None),
    ("ContentView.swift", "sourcecode.swift", False, None),
    ("CorrectionUtil.swift", "sourcecode.swift", False, None),
    ("DepthDataModel.swift", "sourcecode.swift", False, None),
    ("DownloadedVideoPlayerView.swift", "sourcecode.swift", False, None),
    ("Info.plist", "text.plist.xml", False, None), # Info.plist is usually not in build phases
    ("LiDARPOCApp.swift", "sourcecode.swift", False, None),
    ("Model2DViewerView.swift", "sourcecode.swift", False, None),
    ("Model3DViewerView.swift", "sourcecode.swift", False, None),
    ("RecordingsListView.swift", "sourcecode.swift", False, None),
    ("URL+Identifiable.swift", "sourcecode.swift", False, None),
    ("VideoPlaybackView.swift", "sourcecode.swift", False, None),
    ("WelcomeView.swift", "sourcecode.swift", False, None),
    ("Assets.xcassets", "folder.assetcatalog", True, None),
    ("Preview Assets.xcassets", "folder.assetcatalog", True, "Preview Content"),
    ("PlayerView.swift", "sourcecode.swift", False, "SupportingClass"),
]

# generated objects
file_refs = [] # (id, name, path, type)
build_files = [] # (id, fileRefId)
groups = {} # name -> (id, children_ids)
groups[None] = (LIDARPOC_GROUP_ID, []) # Root LiDARPOC group

# Create subgroups
subgroups = ["Preview Content", "SupportingClass"]
for sg in subgroups:
    gid = generate_id()
    groups[sg] = (gid, [])
    groups[None][1].append(gid)

# Create FileRefs and BuildFiles
sources_ids = []
resources_ids = []

for fname, ftype, is_resource, subfolder in files:
    fid = generate_id()
    
    # Path handling
    path = fname
    # if subfolder: path = subfolder + "/" + fname (Not needed if using groups with path set or just children)
    # We will assume groups are just organizational and files are relative to group path if set, 
    # OR we use "name" and "path".
    # Standard Xcode: Group has 'path' (folder name). Children are relative to it.
    
    # But here, LiDARPOC group has path "LiDARPOC".
    # Subgroups:
    # "SupportingClass" group has path "SupportingClass" relative to parent?
    # Let's simplify: FileRefs will have just the filename.
    
    file_refs.append(f'\t\t{fid} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = "{fname}"; sourceTree = "<group>"; }};')
    
    groups[subfolder][1].append(fid)
    
    if fname == "Info.plist":
        continue
        
    bfid = generate_id()
    build_files.append(f'\t\t{bfid} /* {fname} in {"Resources" if is_resource else "Sources"} */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};')
    
    if is_resource:
        resources_ids.append(bfid)
    else:
        sources_ids.append(bfid)

# Construct PBXGroup sections
group_sections = []

# Main Group (unchanged logic)
group_sections.append(f'\t\t{MAIN_GROUP_ID} = {{')
group_sections.append(f'\t\t\tisa = PBXGroup;')
group_sections.append(f'\t\t\tchildren = (')
group_sections.append(f'\t\t\t\t{LIDARPOC_GROUP_ID} /* LiDARPOC */,')
group_sections.append(f'\t\t\t\t{PRODUCTS_GROUP_ID} /* Products */,')
group_sections.append(f'\t\t\t);')
group_sections.append(f'\t\t\tsourceTree = "<group>";')
group_sections.append(f'\t\t}};')

# Products Group (unchanged)
group_sections.append(f'\t\t{PRODUCTS_GROUP_ID} /* Products */ = {{')
group_sections.append(f'\t\t\tisa = PBXGroup;')
group_sections.append(f'\t\t\tchildren = (')
group_sections.append(f'\t\t\t\t{APP_FILE_REF_ID} /* LiDARPOC.app */,')
group_sections.append(f'\t\t\t);')
group_sections.append(f'\t\t\tname = Products;')
group_sections.append(f'\t\t\tsourceTree = "<group>";')
group_sections.append(f'\t\t}};')

# LiDARPOC Group and Subgroups
for gname, (gid, children) in groups.items():
    group_sections.append(f'\t\t{gid} /* {gname if gname else "LiDARPOC"} */ = {{')
    group_sections.append(f'\t\t\tisa = PBXGroup;')
    group_sections.append(f'\t\t\tchildren = (')
    for child in children:
        group_sections.append(f'\t\t\t\t{child},')
    group_sections.append(f'\t\t\t);')
    if gname:
        group_sections.append(f'\t\t\tpath = "{gname}";')
    else:
        group_sections.append(f'\t\t\tpath = LiDARPOC;')
    group_sections.append(f'\t\t\tsourceTree = "<group>";')
    group_sections.append(f'\t\t}};')

# Construct Build Phases
sources_section = f"""\t\t{SOURCES_BUILD_PHASE_ID} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
"""
for bid in sources_ids:
    sources_section += f"\t\t\t\t{bid},\n"
sources_section += """\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};"""

resources_section = f"""\t\t{RESOURCES_BUILD_PHASE_ID} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
"""
for bid in resources_ids:
    resources_section += f"\t\t\t\t{bid},\n"
resources_section += """\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};"""


# File Ref Section
file_ref_section = "\n".join(file_refs)
# Add App File Ref
file_ref_section += f'\n\t\t{APP_FILE_REF_ID} /* LiDARPOC.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LiDARPOC.app; sourceTree = BUILT_PRODUCTS_DIR; }};'

# Build File Section
build_file_section = "\n".join(build_files)

# Configs (Keep existing, hardcoded mostly)
debug_config_id = "8552E46E2EED38770063C5D8"
release_config_id = "8552E46F2EED38770063C5D8"
target_debug_config_id = "8552E4712EED38770063C5D8"
target_release_config_id = "8552E4722EED38770063C5D8"

# We can re-use the exact text from the original file for configs and lists, if we had it handy, or just template it.
# To ensure correctness, I'll use a minimized template based on what I saw in view_file.

pbxproj_content = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{build_file_section}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_ref_section}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{FRAMEWORKS_BUILD_PHASE_ID} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{"".join(group_sections)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{TARGET_ID} /* LiDARPOC */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {TARGET_CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "LiDARPOC" */;
			buildPhases = (
				{SOURCES_BUILD_PHASE_ID} /* Sources */,
				{FRAMEWORKS_BUILD_PHASE_ID} /* Frameworks */,
				{RESOURCES_BUILD_PHASE_ID} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = LiDARPOC;
			productName = LiDARPOC;
			productReference = {APP_FILE_REF_ID} /* LiDARPOC.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT_OBJ_ID} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1520;
				LastUpgradeCheck = 1520;
			}};
			buildConfigurationList = {PROJECT_CONFIG_LIST_ID} /* Build configuration list for PBXProject "LiDARPOC" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {MAIN_GROUP_ID};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 56;
			productRefGroup = {PRODUCTS_GROUP_ID} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TARGET_ID} /* LiDARPOC */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{resources_section}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{sources_section}
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{debug_config_id} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{release_config_id} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{target_debug_config_id} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\\"LiDARPOC/Preview Content\\"";
				DEVELOPMENT_TEAM = WU7L9KSQA2;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = LiDARPOC/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = VisionMetric;
				INFOPLIST_KEY_NSCameraUsageDescription = "This app needs access to the camera to record videos.";
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "This app needs access to the microphone to record audio with videos.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.test.sampleLiDAR;
				PRODUCT_NAME = "$(TARGET_NAME)";
				PROVISIONING_PROFILE_SPECIFIER = "";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{target_release_config_id} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\\"LiDARPOC/Preview Content\\"";
				DEVELOPMENT_TEAM = WU7L9KSQA2;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = LiDARPOC/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = VisionMetric;
				INFOPLIST_KEY_NSCameraUsageDescription = "This app needs access to the camera to record videos.";
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "This app needs access to the microphone to record audio with videos.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.test.sampleLiDAR;
				PRODUCT_NAME = "$(TARGET_NAME)";
				PROVISIONING_PROFILE_SPECIFIER = "";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{PROJECT_CONFIG_LIST_ID} /* Build configuration list for PBXProject "LiDARPOC" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_config_id} /* Debug */,
				{release_config_id} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{TARGET_CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "LiDARPOC" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{target_debug_config_id} /* Debug */,
				{target_release_config_id} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

	}};
	rootObject = {PROJECT_OBJ_ID} /* Project object */;
}}
"""

with open(project_path, "w") as f:
    f.write(pbxproj_content)

print(f"Successfully repaired {project_path}")
