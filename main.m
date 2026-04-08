%% Phase 1: Signal Preprocessing

[y1, Fs1] = audioread('Short_FM9090.wav');
[y2, Fs2] = audioread('Short_BBCArabic2.wav');

% 2. Safety Check: Ensure sampling frequencies are identical(all the sampling freq provided are 44.1khz so this check can be deleted)
if Fs1 ~= Fs2
    disp('Warning: Sampling frequencies are NOT equal!');
    disp(['Fs1 = ', num2str(Fs1), ' Hz, Fs2 = ', num2str(Fs2), ' Hz']);

    % Fix the issue by resampling the second signal to match the first one
    disp('Resampling the second audio file to match Fs1...');
    y2 = resample(y2, Fs1, Fs2);
else
    disp(['Success: Sampling frequencies match perfectly at ', num2str(Fs1), ' Hz.']);
end

% Set the universal Fs to be used for the rest of the project
Fs = Fs1;
% 2. Convert Stereo to Mono (adding Left and Right channels)
m1 = y1(:, 1) + y1(:, 2);
m2 = y2(:, 1) + y2(:, 2);

% 3. Zero-Padding to make signals equal length
L1 = length(m1);
L2 = length(m2);
maxLength = max(L1, L2);

% Pad the shorter signal with zeros at the end
m1 = [m1; zeros(maxLength - L1, 1)];
m2 = [m2; zeros(maxLength - L2, 1)];



% --- Automatic Baseband Bandwidth Estimation (99% Power Method) ---
% The project requires estimating the baseband bandwidth[cite: 35].
% We use the 99% power rule on the positive frequencies of the FFT.

L_m = length(m1); % Use the original, un-interpolated signal for true baseband BW
f_axis_baseband = (0 : floor(L_m/2)-1) * (Fs / L_m); % Positive frequency axis

% 1. Get the FFT and calculate the Power Spectral Density
M1_fft = fft(m1);
M1_positive = M1_fft(1:floor(L_m/2)); % Take only positive frequencies
Power_Spectrum = abs(M1_positive).^2; % Power is magnitude squared

% 2. Calculate Cumulative Power
Total_Power = sum(Power_Spectrum);
Cumulative_Power = cumsum(Power_Spectrum);

% 3. Find the frequency index where 99% of the total power is reached
power_threshold = 0.99 * Total_Power;
bw_index = find(Cumulative_Power >= power_threshold, 1, 'first');

% 4. Extract the actual bandwidth frequency
BW_estimated = f_axis_baseband(bw_index);

disp(['Estimated 99% Power Bandwidth of Signal 1: ', num2str(BW_estimated), ' Hz']);

% --- Plotting the Baseband Spectrum (Required) ---
% We plot the spectrum as requested [cite: 33] and add a marker for our estimated BW.
figure;
plot(f_axis_baseband, abs(M1_positive));
hold on;
xline(BW_estimated, 'r--', 'LineWidth', 2); % Draws a red dashed line at the exact BW
hold off;

title('Baseband Spectrum (Audio 1) with 99% Power BW');
xlabel('Frequency (Hz)');
ylabel('Magnitude');
xlim([0 20000]); % Limit x-axis to human hearing range (20 kHz)
legend('Signal Spectrum', ['99% BW \approx ', num2str(round(BW_estimated)), ' Hz']);
grid on;




% 4. Interpolation (Increasing Sampling Frequency)
% Standard audio Fs is usually 44.1 kHz or 48 kHz.
% Our highest carrier frequency for two signals is 130 kHz.
% To satisfy Nyquist, Fs must be > 2 * 130 kHz (260 kHz).
% The project suggests increasing by a factor of 10.


% --- Justification for Interpolation Factor ---
% The maximum bandwidth of the baseband signal was verified to be approx 7 kHz.
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
m1_up = interp(m1, interp_factor);
m2_up = interp(m2, interp_factor);

% Create a time vector for our new upsampled signals
t = (0:length(m1_up)-1)' * Ts;

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
c1 = cos(2 * pi * F0 * t);
c2 = cos(2 * pi * F1 * t);

% 3. DSB-SC Modulation
% In DSB-SC, the modulated signal is just the message multiplied by the carrier.
% We use '.*' for element-by-element multiplication of the arrays.
mod1 = m1_up .* c1;
mod2 = m2_up .* c2;

% 4. Construct the FDM Signal
% Add the modulated signals together to transmit them over a single "channel"
fdm_signal = mod1 + mod2;

% Optional: Plotting the FDM Spectrum to verify
% The project suggests plotting the spectrum to estimate bandwidth [cite: 33, 35]
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
target_frequencies = [F0, F1];
F_IF = 15000; % Intermediate Frequency (15 kHz)
filter_order = 4;
for i = 1:length(target_frequencies)
    F_target = target_frequencies(i);
    disp(['--- Demodulating Station ', num2str(i), ' (', num2str(F_target/1000), ' kHz) ---']);

    %% --- Phase 3: RF Stage ---
    % 1. Filter Specs (using your automatically estimated BW)
    BW_guard = BW_estimated * 1.05;
    f_low = F_target - BW_guard;
    f_high = F_target + BW_guard;

    % 2. Design and Apply RF Filter
    rf_specs = fdesign.bandpass('N,F3dB1,F3dB2', filter_order, f_low, f_high, Fs_new);
    rf_filter = design(rf_specs, 'butter');
    rf_output = filter(rf_filter, fdm_signal);

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
% info2 = audioinfo('Short_BBCArabic2.wav');
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