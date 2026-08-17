import org.gradle.api.GradleException
import org.gradle.api.tasks.JavaExec

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val productionSigningEnvironment = mapOf(
    "MD4A_ANDROID_KEYSTORE_FILE" to System.getenv("MD4A_ANDROID_KEYSTORE_FILE"),
    "MD4A_ANDROID_STORE_PASSWORD" to System.getenv("MD4A_ANDROID_STORE_PASSWORD"),
    "MD4A_ANDROID_KEY_ALIAS" to System.getenv("MD4A_ANDROID_KEY_ALIAS"),
    "MD4A_ANDROID_KEY_PASSWORD" to System.getenv("MD4A_ANDROID_KEY_PASSWORD"),
)
val productionSigningRequested = productionSigningEnvironment.values.any { !it.isNullOrBlank() }
val missingProductionSigningValues = productionSigningEnvironment.filterValues { it.isNullOrBlank() }.keys
val productionSigningReady = missingProductionSigningValues.isEmpty()

android {
    val redirectedBuildDir = providers.gradleProperty("md4aBuildDir")
    if (redirectedBuildDir.isPresent) {
        layout.buildDirectory.set(file(redirectedBuildDir.get()))
    }

    namespace = "app.md4a"
    compileSdk = 35
    testBuildType = "benchmark"

    defaultConfig {
        applicationId = "app.md4a"
        minSdk = 26
        targetSdk = 35
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        versionCode = System.getenv("MD4A_VERSION_CODE")?.toIntOrNull()
            ?: if (System.getenv("MD4A_VERSION_CODE") == null) 1
            else error("MD4A_VERSION_CODE must be a valid integer")
        versionName = System.getenv("MD4A_VERSION_NAME") ?: "0.1.0"

        externalNativeBuild {
            cmake {
                arguments("-DANDROID_STL=none")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (productionSigningReady) {
            create("production") {
                storeFile = file(productionSigningEnvironment.getValue("MD4A_ANDROID_KEYSTORE_FILE")!!)
                storePassword = productionSigningEnvironment.getValue("MD4A_ANDROID_STORE_PASSWORD")
                keyAlias = productionSigningEnvironment.getValue("MD4A_ANDROID_KEY_ALIAS")
                keyPassword = productionSigningEnvironment.getValue("MD4A_ANDROID_KEY_PASSWORD")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (productionSigningReady) signingConfig = signingConfigs.getByName("production")
        }
        create("signedBeta") {
            initWith(getByName("release"))
            if (productionSigningReady) signingConfig = signingConfigs.getByName("production")
            matchingFallbacks += "release"
        }
        create("benchmark") {
            initWith(getByName("release"))
            isDebuggable = false
            isProfileable = true
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += "release"
        }
    }

    sourceSets {
        getByName("benchmark") {
            java.srcDir("src/benchmark/java")
            manifest.srcFile("src/benchmark/AndroidManifest.xml")
        }
        getByName("testBenchmark") {
            java.srcDir("src/testBenchmark/java")
        }
        getByName("androidTestBenchmark") {
            java.srcDir("src/androidTestBenchmark/java")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.compose.material3:material3:1.3.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    testImplementation("junit:junit:4.13.2")
    "testBenchmarkImplementation"("junit:junit:4.13.2")
    "androidTestBenchmarkImplementation"("androidx.test:runner:1.6.2")
    "androidTestBenchmarkImplementation"("androidx.test:rules:1.6.1")
    "androidTestBenchmarkImplementation"("androidx.test.ext:junit:1.2.1")
}

val validateProductionSigning by tasks.registering {
    group = "verification"
    description = "Validate production Android signing environment"
    doLast {
        if (!productionSigningReady) {
            throw GradleException(
                "Production signing requires all of: ${productionSigningEnvironment.keys.joinToString()}. " +
                    "Missing: ${missingProductionSigningValues.joinToString()}.",
            )
        }
        val keystore = file(productionSigningEnvironment.getValue("MD4A_ANDROID_KEYSTORE_FILE")!!)
        if (!keystore.isFile) {
            throw GradleException("MD4A_ANDROID_KEYSTORE_FILE does not exist or is not a file: $keystore")
        }
    }
}

tasks.matching { it.name == "preSignedBetaBuild" }.configureEach {
    dependsOn(validateProductionSigning)
}
if (productionSigningRequested) {
    tasks.matching { it.name == "preReleaseBuild" }.configureEach {
        dependsOn(validateProductionSigning)
    }
}

if (productionSigningRequested && !productionSigningReady) {
    logger.warn(
        "Production Android signing was requested but is incomplete; signedBeta packaging will fail. " +
            "Missing: ${missingProductionSigningValues.joinToString()}",
    )
}

androidComponents {
    onVariants(selector().withBuildType("benchmark")) { variant ->
        tasks.register<JavaExec>("largeDocumentBenchmark") {
            group = "verification"
            description = "Benchmark the production large-document buffer"
            dependsOn("compileBenchmarkKotlin")
            classpath(variant.runtimeConfiguration)
            classpath(layout.buildDirectory.dir("tmp/kotlin-classes/benchmark"))
            mainClass.set("app.md4a.benchmark.BenchmarkCli")
            args(
                "--fixture=${providers.gradleProperty("fixture").orNull.orEmpty()}",
                "--warmups=${providers.gradleProperty("warmups").orElse("1").get()}",
                "--repetitions=${providers.gradleProperty("repetitions").orElse("5").get()}",
            )
        }
    }
}
