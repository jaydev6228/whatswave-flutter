allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Some third-party plugins (e.g. flutter_ringtone_player) pin their own
// Android library module to an old compileSdk (33) instead of deferring to
// flutter.compileSdkVersion like the app itself does, so the AndroidX
// versions Gradle unifies across the whole build (which those plugins'
// declared dependencies then also resolve to) end up requiring API 34+ that
// the plugin's own module wasn't compiled against -- causing
// checkDebugAarMetadata to fail. Forcing every Android *library* subproject
// (never :app, which manages its own compileSdk directly) to compile
// against the app's own compileSdk (36) resolves that mismatch without
// having to patch each plugin individually.
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.findByName("android")?.let { androidExtension ->
                if (androidExtension is com.android.build.gradle.BaseExtension) {
                    androidExtension.compileSdkVersion(36)
                }
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
