%% Phase 1: Signal Preprocessing

[y1, Fs1] = audioread('Short_FM9090.wav');
[y2, Fs2] = audioread('Short_BBCArabic2.wav');

% 2. Safety Check: Ensure sampling frequencies are identical(all the samples provided are 44.1khz so this check can be deleted)
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

