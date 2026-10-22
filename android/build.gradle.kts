buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Lets the root script align plugin subprojects' compileSdk (see
        // below) without editing each plugin's own build.gradle.
        classpath("com.android.tools.build:gradle:8.13.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.all {
        resolutionStrategy {
            // The integration_test plugin requests dynamic versions
            // (e.g. androidx.test:runner:1.2+); every build then needs a
            // live metadata lookup against Maven Central, which fails
            // whenever the network blips. Pin them.
            force("androidx.test:runner:1.6.2")
            force("androidx.test:core:1.6.1")
            force("androidx.test:monitor:1.7.2")
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
    // Transitive androidx.core (1.15+) pulled by newer plugins requires
    // compileSdk 35+, while older plugins in the tree still declare 34.
    // Align every Android subproject on the app's compileSdk.
    val raiseCompileSdk: (Project) -> Unit = { p ->
        val androidExt = p.extensions.findByName("android")
        when (androidExt) {
            is com.android.build.api.dsl.LibraryExtension ->
                if ((androidExt.compileSdk ?: 0) < 36) {
                    androidExt.compileSdk = 36
                }
            is com.android.build.api.dsl.ApplicationExtension ->
                if ((androidExt.compileSdk ?: 0) < 36) {
                    androidExt.compileSdk = 36
                }
        }
    }
    if (project.state.executed) {
        raiseCompileSdk(project)
    } else {
        project.afterEvaluate(object : org.gradle.api.Action<Project> {
            override fun execute(evaluated: Project) {
                raiseCompileSdk(evaluated)
            }
        })
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
