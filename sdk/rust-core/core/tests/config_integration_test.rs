use tracelet_core::config::EngineConfig;

#[test]
fn test_default_configurations() {
    let config = EngineConfig::default();

    // Verify Geo defaults
    assert_eq!(config.geo.desired_accuracy, 0); // 0 = High by default
    assert_eq!(config.geo.distance_filter, 10.0);
    assert_eq!(config.geo.stationary_radius, 25.0);
    assert_eq!(config.geo.location_timeout, 60);
    assert_eq!(config.geo.elasticity_multiplier, 1.0);
    assert_eq!(config.geo.stop_after_elapsed_minutes, -1);
    assert_eq!(config.geo.max_monitored_geofences, -1);

    // Verify Motion defaults
    assert_eq!(config.motion.activity_recognition_interval, 1000);
    assert_eq!(config.motion.minimum_activity_recognition_confidence, 75);
    assert_eq!(config.motion.stop_detection_delay, 0);
    assert_eq!(config.motion.stop_on_stationary, false);
    assert_eq!(config.motion.motion_detection_mode, 0);
    // 0.9, not 1.5: the old default sat above an average walking pace of
    // ~1.4 m/s, so the median pedestrian was classified as stationary.
    assert_eq!(config.motion.speed_moving_threshold, 0.9);
    // Unset by default; the hosts derive it at 65 % of the moving threshold.
    assert_eq!(config.motion.speed_stationary_threshold, 0.0);
    assert_eq!(config.motion.speed_stationary_delay, 180);
    assert_eq!(config.motion.speed_wake_confirm_count, 1);
    assert_eq!(config.motion.still_sample_count, 25);

    // Verify Http defaults
    assert_eq!(config.http.url, None);
    assert_eq!(config.http.auto_sync, false);
    assert_eq!(config.http.max_batch_size, 0);
    assert_eq!(config.http.max_retries, 0);
    assert_eq!(config.http.ssl_pinning_certificates, None);
    assert_eq!(config.http.ssl_pinning_fingerprints, None);

    // Verify Persistence defaults
    assert_eq!(config.persistence.max_records_to_persist, -1);
}

#[test]
fn test_config_overrides() {
    let mut config = EngineConfig::default();

    // Override Geo bounds
    config.geo.desired_accuracy = 100; // Custom
    config.geo.distance_filter = 10.0;
    config.geo.stop_after_elapsed_minutes = 15;
    config.geo.battery_budget_per_hour = 10.0;
    
    // Override Motion bounds
    config.motion.activity_recognition_interval = 5000;
    config.motion.speed_moving_threshold = 2.0;

    // Validate mutations applied
    assert_eq!(config.geo.distance_filter, 10.0);
    assert_eq!(config.geo.stop_after_elapsed_minutes, 15);
    assert_eq!(config.geo.battery_budget_per_hour, 10.0);
    assert_eq!(config.motion.activity_recognition_interval, 5000);
    assert_eq!(config.motion.speed_moving_threshold, 2.0);
}

#[test]
fn test_config_json_deserialization() {
    let json = r#"
    {
        "geo": {
            "desiredAccuracy": 10,
            "distanceFilter": 50.5,
            "stopAfterElapsedMinutes": 30
        },
        "motion": {
            "activityRecognitionInterval": 2000,
            "stopOnStationary": false
        },
        "http": {
            "url": "https://api.example.com/sync",
            "sslPinningFingerprints": ["AA:BB:CC"]
        }
    }
    "#;

    let config: EngineConfig = serde_json::from_str(json).expect("Failed to parse JSON");

    assert_eq!(config.geo.desired_accuracy, 10);
    assert_eq!(config.geo.distance_filter, 50.5);
    assert_eq!(config.geo.stop_after_elapsed_minutes, 30);

    assert_eq!(config.motion.activity_recognition_interval, 2000);
    assert_eq!(config.motion.stop_on_stationary, false);

    assert_eq!(config.http.url, Some("https://api.example.com/sync".to_string()));
    assert_eq!(config.http.ssl_pinning_fingerprints, Some(vec!["AA:BB:CC".to_string()]));
}
