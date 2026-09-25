allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Force the Start.io native SDK to a version that compiles against API 36
    // (the plugin pulls 5.3.2 which needs API 37, not available yet).
    configurations.all {
        resolutionStrategy {
            force("com.startapp:inapp-sdk:5.1.0")
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
