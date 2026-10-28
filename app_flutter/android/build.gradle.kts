allprojects {
    repositories {
        val googleMavenMirror = providers.gradleProperty("googleMavenMirror").orNull
        if (googleMavenMirror != null) {
            maven { url = uri(googleMavenMirror) }
        } else {
            google()
        }
        mavenCentral()
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

// 统一强制所有插件的 compileSdk 为 36，解决旧插件版本不兼容问题
subprojects {
    project.evaluationDependsOn(":app")
    project.plugins.withId("com.android.library") {
        project.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
