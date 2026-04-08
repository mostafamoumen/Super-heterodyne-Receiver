%% Phase 1: Signal Preprocessing

[message_sterio1, Fs1] = audioread('Short_FM9090.wav');
[message_sterio2, Fs2] = audioread('Short_BBCArabic2.wav');

% 2. Safety Check: Ensure sampling frequencies are identical(all the sampling freq provided are 44.1khz so this check can be deleted)
if Fs1 ~= Fs2
    disp('Warning: Sampling frequencies are NOT equal!');
    disp(['Fs1 = ', num2str(Fs1), ' Hz, Fs2 = ', num2str(Fs2), ' Hz']);

    % Fix the issue by resampling the second signal to match the first one
    disp('Resampling the second audio file to match Fs1...');
    message_sterio2 = resample(message_sterio2, Fs1, Fs2); %signalout = resample(input signal,upsampling factor ,downsampling factor),, for further revision
else
    disp(['Success: Sampling frequencies match perfectly at ', num2str(Fs1), ' Hz.']);
end

% Set the universal Fs to be used for the rest of the project
Fs = Fs1;
% 2. Convert Stereo to Mono (adding Left and Right channels)
message_mono1 = message_sterio1(:, 1) + message_sterio1(:, 2);
message_mono2 = message_sterio2(:, 1) + message_sterio2(:, 2);

% 3. Zero-Padding to make signals equal length
L1 = length(message_mono1);
L2 = length(message_mono2);
maxLength = max(L1, L2);

% Pad the shorter signal with zeros at the end
message_mono1 = [message_mono1; zeros(maxLength - L1, 1)];
message_mono2 = [message_mono2; zeros(maxLength - L2, 1)];



% --- Automatic Baseband Bandwidth Estimation (99% Power Method) ---

L_m = length(message_mono1);
f_axis_baseband = (0 : floor(L_m/2)-1) * (Fs / L_m); % Positive frequency axis

% Calculate for Signal 1
M1_fft = fft(message_mono1);
M1_positive = M1_fft(1:floor(L_m/2));
Power_Spectrum1 = abs(M1_positive).^2;
Total_Power1 = sum(Power_Spectrum1);
Cumulative_Power1 = cumsum(Power_Spectrum1);
bw_index1 = find(Cumulative_Power1 >= 0.99 * Total_Power1, 1, 'first');
BW1 = f_axis_baseband(bw_index1);

% Calculate for Signal 2
M2_fft = fft(message_mono2);
M2_positive = M2_fft(1:floor(L_m/2));
Power_Spectrum2 = abs(M2_positive).^2;
Total_Power2 = sum(Power_Spectrum2);
Cumulative_Power2 = cumsum(Power_Spectrum2);
bw_index2 = find(Cumulative_Power2 >= 0.99 * Total_Power2, 1, 'first');
BW2 = f_axis_baseband(bw_index2);

% Store both bandwidths in an array so the receiver can use them later
BW_array = [BW1, BW2];

disp(['Estimated 99% Power BW of Signal 1: ', num2str(BW1), ' Hz']);
disp(['Estimated 99% Power BW of Signal 2: ', num2str(BW2), ' Hz']);

% --- Plotting the Baseband Spectrum for Signal 1 (Required) ---
figure;
plot(f_axis_baseband, abs(M1_positive));
hold on;
xline(BW1, 'r--', 'LineWidth', 2);
hold off;
title('Baseband Spectrum (Audio 1) with 99% Power BW');
xlabel('Frequency (Hz)'); ylabel('Magnitude'); xlim([0 20000]);
legend('Signal Spectrum', ['99% BW \approx ', num2str(round(BW1)), ' Hz']);
grid on;


% The maximum bandwidth of the baseband signal(the wider one) was verified to be approx 7 kHz.
% In DSB-SC modulation, the upper sideband reaches F_carrier_max + BW.
% For our FDM signal, the highest frequency component is F_max = 130 kHz + 7 kHz = 137 kHz.
% According to the Nyquist-Shannon sampling theorem, the theoretical minimum
% sampling frequency required to prevent aliasing is Fs > 2 * F_max (2 * 137 kHz = 274 kHz).
% By using an interpolation factor of 10 (e.g., 44.1 kHz * 10 = 441 kHz),
% we safely exceed the 274 kHz Nyquist minimum while keeping integer multiplication,
% which also improves the performance of the digital BPF/LPF filters in later stages.

interp_factor = 10;
Fs_new = Fs * interp_factor;
Ts = 1 / Fs_new; % New sampling interval

% Use 'interp' to increase the number of samples
message_mono1_up = interp(message_mono1, interp_factor);
message_mono2_up = interp(message_mono2, interp_factor);

% Create a time vector for our new upsampled signals
t = (0:length(message_mono1_up)-1)' * Ts;

%% Phase 2: AM Modulation (DSB-SC) and FDM Construction

% 1. Define Carrier Frequencies
% The first carrier is 100 KHz
F0 = 100000;

% The second carrier is F0 + delta_F (where delta_F is 30 KHz)
delta_F = 30000;
F1 = F0 + delta_F; % This equals 130 KHz

% 2. Generate Carrier Signals
% Using the time vector 't' generated in Phase 1
% Math equivalent: cos(w_n * t)
carrier1 = cos(2 * pi * F0 * t);
carrier2 = cos(2 * pi * F1 * t);

% 3. DSB-SC Modulation
% In DSB-SC, the modulated signal is just the message multiplied by the carrier.
% We use '.*' for element-by-element multiplication of the arrays.
modulated_message1 = message_mono1_up .* carrier1;
modulated_message2 = message_mono2_up .* carrier2;

% 4. Construct the FDM Signal
% Add the modulated signals together to transmit them over a single "channel"
fdm_signal = modulated_message1 + modulated_message2;

% Optional: Plotting the FDM Spectrum to verify
% The project suggests plotting the spectrum to estimate bandwidth
L_fdm = length(fdm_signal);
f_axis = (-L_fdm/2 : (L_fdm/2)-1) * (Fs_new / L_fdm); % Frequency axis centered at 0

FDM_Spectrum = fftshift(fft(fdm_signal)); % Move 0 frequency to center

figure;
plot(f_axis, abs(FDM_Spectrum));
title('Spectrum of the FDM Signal');
xlabel('Frequency (Hz)');
ylabel('Magnitude');
grid on;





%% Phase 3 to 5: The Receiver - Demodulating Both Stations

% We put our carrier frequencies in an array to loop through them
%% Phase 3 to 5: The Receiver - Demodulating Both Stations

target_frequencies = [F0, F1];
F_IF = 15000; % Intermediate Frequency (15 kHz)
filter_order = 4;

for i = 1:length(target_frequencies)
    F_target = target_frequencies(i);

    % Grab the specific bandwidth for the current station
    BW_estimated = BW_array(i);

    disp(['--- Demodulating Station ', num2str(i), ' (', num2str(F_target/1000), ' kHz) ---']);

    %% --- Phase 3: RF Stage ---
    % 1. Filter Specs
    BW_guard = BW_estimated * 1.05;
    f_low = F_target - BW_guard;
    f_high = F_target + BW_guard;

    % 2. Design and Apply RF Filter
    rf_specs = fdesign.bandpass('N,F3dB1,F3dB2', filter_order, f_low, f_high, Fs_new);
    rf_filter = design(rf_specs, 'butter');
    rf_output = filter(rf_filter, fdm_signal);



    % --- Visualizing the RF Filter over the FDM Spectrum ---
    % 1. Extract the filter's frequency response using freqz
    [h, ~] = freqz(rf_filter, L_fdm, 'whole', Fs_new);
    filter_shape = fftshift(abs(h)); % Shift to match our centered f_axis

    % 2. Scale the filter's height so it matches the FDM spectrum visually
    scaled_filter = filter_shape * max(abs(FDM_Spectrum));

    % 3. Plot the FDM signal and overlay the red filter shape
    figure;
    plot(f_axis, abs(FDM_Spectrum), 'b'); % The blue FDM signal (both stations)
    hold on;
    plot(f_axis, scaled_filter, 'r', 'LineWidth', 2); % The red filter "window"
    hold off;

    title(['RF Filter Shape over FDM Spectrum - Station ', num2str(i)]);
    xlabel('Frequency (Hz)');
    ylabel('Magnitude');
    legend('FDM Signal (Both Stations)', 'RF Filter Passband');
    xlim([50000 180000]); % Zoom in specifically to the 100 kHz - 130 kHz neighborhood
    grid on;



    % 3. Plot RF Spectrum
    figure;
    plot(f_axis, abs(fftshift(fft(rf_output))));
    title(['RF Output Spectrum - Station ', num2str(i), ' (Tuned to ', num2str(F_target/1000), ' kHz)']);
    xlabel('Frequency (Hz)'); ylabel('Magnitude'); grid on;

    %% --- Phase 4: Oscillator, Mixer, and IF Stage ---
    % 1. Mixer
    F_osc = F_target + F_IF;
    osc_signal = cos(2 * pi * F_osc * t);
    mixer_output = rf_output .* osc_signal;

    % 2. Design and Apply IF Filter (Centered at 15 kHz)
    f_low_IF = F_IF - BW_guard;
    f_high_IF = F_IF + BW_guard;
    if_specs = fdesign.bandpass('N,F3dB1,F3dB2', filter_order, f_low_IF, f_high_IF, Fs_new);
    if_filter = design(if_specs, 'butter');
    if_output = filter(if_filter, mixer_output);

    % 3. Plot IF Spectrum
    figure;
    plot(f_axis, abs(fftshift(fft(if_output))));
    title(['IF Output Spectrum - Station ', num2str(i), ' (Centered at 15 kHz)']);
    xlabel('Frequency (Hz)'); ylabel('Magnitude'); xlim([-50000 50000]); grid on;

    %% --- Phase 5: Baseband Detection & Audio Output ---
    % 1. Baseband Mixing
    baseband_carrier = cos(2 * pi * F_IF * t);
    baseband_mixed = if_output .* baseband_carrier;

    % 2. Design and Apply Low-Pass Filter
    lpf_specs = fdesign.lowpass('N,F3dB', filter_order, BW_guard, Fs_new);
    lpf_filter = design(lpf_specs, 'butter');
    demodulated_signal = filter(lpf_filter, baseband_mixed);

    % 3. Plot Final Baseband Spectrum
    figure;
    plot(f_axis, abs(fftshift(fft(demodulated_signal))));
    title(['Final Demodulated Spectrum - Station ', num2str(i)]);
    xlabel('Frequency (Hz)'); ylabel('Magnitude'); xlim([-20000 20000]); grid on;

    % 4. Audio Playback and Saving
    final_audio = downsample(demodulated_signal, interp_factor);
    normalized_audio = final_audio / max(abs(final_audio));

    % Save to disk dynamically
    filename = ['Demodulated_Station', num2str(i), '.wav'];
    audiowrite(filename, normalized_audio, Fs);
    disp(['Saved successfully as: ', filename]);

    % Optional: You can play the sound of the current station (uncomment to test)
    sound(normalized_audio, Fs);
    pause(10); % Pause for 10 seconds to listen before moving to the next station
end

disp('--- All stations successfully demodulated and saved! ---');


% info1 = audioinfo('Short_FM9090.wav');
% info2 = audioinfo('Short_BBCArabicarrier2.wav');
%
% n_samples1 = info1.TotalSamples;
% n_channels1 = info1.NumChannels;
%
% n_samples2 = info2.TotalSamples;
% n_channels2 = info2.NumChannels;
%
% disp(n_samples1)
% disp(n_channels1)
%
% disp(n_samples2)
% disp(n_channels2)
% this was just for testing ,,,(n_samples1=697536, n_samples2=740544 so we had to zeropad at the end of the shorter one)