clc;
clear;
close all;

% Read audio file
[data, Fs] = audioread('Short_BBCArabic2.wav');

% Convert to mono if stereo
if size(data,2) == 2
    data = mean(data, 2);
end

% Length of signal
N = length(data);

% FFT
X = fft(data);

% Frequency axis
f = (0:N-1)*(Fs/N);

% Take only positive frequencies
half_N = floor(N/2);
X_half = abs(X(1:half_N));
f_half = f(1:half_N);

% Normalize magnitude
X_half = X_half / max(X_half);

% -------- Plot Spectrum --------
figure;
plot(f_half, X_half);
xlabel('Frequency (Hz)');
ylabel('Normalized Magnitude');
title('Frequency Spectrum of Audio');
grid on;

% -------- Energy-Based Bandwidth (99%) --------
power_spectrum = X_half.^2;

% Normalize total power
power_spectrum = power_spectrum / sum(power_spectrum);

% Cumulative sum of power
cumulative_power = cumsum(power_spectrum);

% Find frequency where 99% of energy is contained
idx_99 = find(cumulative_power >= 0.99, 1);

BW_99 = f_half(idx_99);

% Display result
fprintf('99%% Power Bandwidth = %.2f Hz\n', BW_99);

% -------- Optional: Mark BW on Plot --------
hold on;
xline(BW_99, 'r--', 'LineWidth', 2);
legend('Spectrum', '99% BW');