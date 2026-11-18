# An Educational Digital Twin for a Line-Following Car

This project presents an educational digital twin prototype for a line-following car. The idea comes from youth education and training activities in which students build their own line-following cars. Beyond making a car follow a track, the aim is to help students understand how sensor readings, control decisions and wheel motion are connected.

The prototype uses a seven-layer software architecture covering physical simulation, data acquisition, communication, data management, twin modeling, diagnostic services and application visualization. A Python vehicle simulation generates observations at 50 Hz in simulation time. An operational MQTT broker transfers telemetry, commands and acknowledgements between the source and the receiver.

The digital twin generates healthy wheel-speed references, predicts motion and compares these predictions with received observations. The interface displays sensor readings, PID components, signed wheel-speed residuals, position innovation, measured trajectories and healthy-reference replay. Diagnostic services use consecutive observations to identify drive-response deviations and support controlled parameter comparisons.

The video walkthrough introduces the educational motivation and demonstrates healthy operation, a simulated 20% reduction in left-wheel response, telemetry interruption and recovery, and source command acknowledgements. These experiments connect visible behavior with the signals and calculations behind it.

The Python validation suite contains 19 automated tests covering model calculations, data handling, real MQTT communication and numerical comparison with MATLAB reference traces. The current prototype uses a software-simulated vehicle. Connecting it to student-built physical cars remains a future development step requiring hardware acquisition, calibration and physical validation.

The project provides a foundation for making robotics concepts more observable and explainable in hands-on engineering education.
