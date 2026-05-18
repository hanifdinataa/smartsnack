<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'token' => env('POSTMARK_TOKEN'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'resend' => [
        'key' => env('RESEND_KEY'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    // Optional external classifier (XGBoost/Python service).
    'xgboost_classifier' => [
        'endpoint' => env('ML_XGBOOST_ENDPOINT'),
    ],

    'open_food_facts' => [
        'enabled' => env('OPEN_FOOD_FACTS_ENABLED', true),
        'timeout' => (int) env('OPEN_FOOD_FACTS_TIMEOUT', 8),
    ],

    'label_gizi_service' => [
        'endpoint' => env('LABEL_GIZI_ENDPOINT', env('NUTRITION_VISION_ENDPOINT', 'http://127.0.0.1:5060')),
        'timeout' => (int) env('LABEL_GIZI_TIMEOUT', env('NUTRITION_VISION_TIMEOUT', 120)),
    ],

    'iot_sensor' => [
        'endpoint' => env('IOT_SENSOR_ENDPOINT', ''),
        'heart_rate_endpoint' => env('IOT_HEART_RATE_ENDPOINT', ''),
        'temperature_endpoint' => env('IOT_TEMPERATURE_ENDPOINT', ''),
    ],

    'diabetes_xgboost' => [
        'endpoint' => env('DIABETES_XGBOOST_ENDPOINT', ''),
        'require_model' => env('DIABETES_XGBOOST_REQUIRE_MODEL', true),
    ],

    'mqtt' => [
        'host' => env('MQTT_HOST', '127.0.0.1'),
        'port' => (int) env('MQTT_PORT', 1883),
        'username' => env('MQTT_USERNAME', ''),
        'password' => env('MQTT_PASSWORD', ''),
        'client_id_prefix' => env('MQTT_CLIENT_ID_PREFIX', 'smartsnack_backend'),
        'timeout_seconds' => (int) env('MQTT_TIMEOUT_SECONDS', 120),
        'device_id' => env('MQTT_DEVICE_ID', 'esp32_health_01'),
    ],

    'snack_box' => [
        'device_id' => env('SNACK_BOX_DEVICE_ID', env('MQTT_DEVICE_ID', 'esp32_health_01')),
        'servo_open_duration_ms' => (int) env('SNACK_BOX_SERVO_OPEN_DURATION_MS', 3000),
        'min_remaining_to_open_no' => (float) env('SNACK_BOX_MIN_REMAINING_TO_OPEN_NO', 3),
        'min_remaining_to_open_yes' => (float) env('SNACK_BOX_MIN_REMAINING_TO_OPEN_YES', 3),
    ],

];
