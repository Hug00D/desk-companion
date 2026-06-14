allprojects {
    subprojects {
        configurations.all {
            resolutionStrategy.eachDependency {
                // Kotlin 必須用雙引號，且用 .group 或 .name
                if (requested.group == "androidx.core" && requested.name == "core-ktx") {
                    // 函式呼叫必須加括號
                    useVersion("1.13.1")
                }
            }
        }

        // 強制拉升所有子專案的編譯版本
        afterEvaluate {
            val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            android?.apply {
                compileSdkVersion(36)
                buildToolsVersion("34.0.0")
            }

            if (name == "camera_android_camerax") {
                dependencies.add(
                    "implementation",
                    "androidx.concurrent:concurrent-futures:1.2.0"
                )
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
