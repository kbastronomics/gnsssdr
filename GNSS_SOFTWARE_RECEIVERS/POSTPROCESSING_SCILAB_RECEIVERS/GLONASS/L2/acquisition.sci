function acqResults = acquisition(longSignal, settings)
//Function performs cold start acquisition on the collected "data". It
//searches for GLONASS signals of all frequencu channels, which are listed 
//in field "acqFCHList" in the settings structure. Function saves code phase
//and frequency of the detected signals in the "acqResults" structure.
//
//acqResults = acquisition(longSignal, settings)
//
//   Inputs:
//       longSignal    - 11 ms of raw signal from the front-end 
//       settings      - Receiver settings. Provides information about
//                       sampling and intermediate frequencies and other
//                       parameters including the list of the satellites to
//                       be acquired.
//   Outputs:
//       acqResults    - Function saves code phases and frequencies of the 
//                       detected signals in the "acqResults" structure. The
//                       field "carrFreq" is set to 0 if the signal is not
//                       detected for the given FCH number. (FCH = frequency 
//                       channel)
 
//--------------------------------------------------------------------------
//                           SoftGNSS v3.0 GLONASS version
// 
// Copyright (C) Darius Plausinaitis and Dennis M. Akos
// Written by Darius Plausinaitis and Dennis M. Akos
// Based on Peter Rinder and Nicolaj Bertelsen
// Updated and converted to scilab 5.3.0 by Artyom Gavrilov
//--------------------------------------------------------------------------
//This program is free software; you can redistribute it and/or
//modify it under the terms of the GNU General Public License
//as published by the Free Software Foundation; either version 2
//of the License, or (at your option) any later version.
//
//This program is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU General Public License for more details.
//
//You should have received a copy of the GNU General Public License
//along with this program; if not, write to the Free Software
//Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
//USA.
//--------------------------------------------------------------------------

// Initialization =========================================================
  
  // Find number of samples per spreading code
  samplesPerCode = round(settings.samplingFreq / ...
                         (settings.codeFreqBasis / settings.codeLength));
  
  // Create two "settings.acqCohIntegration" msec vectors of data
  // to correlate with
  signal1 = longSignal(1 : settings.acqCohIntegration*samplesPerCode);
  signal2 = longSignal(settings.acqCohIntegration*samplesPerCode+1 :...
                       2*settings.acqCohIntegration*samplesPerCode);
  
  // Find sampling period
  ts = 1 / settings.samplingFreq;
  
  // Find phase points of the local carrier wave 
  phasePoints = ...
          (0 : (settings.acqCohIntegration*samplesPerCode-1)) * 2 * %pi * ts;
  
  // Number of the frequency bins for the given acquisition band (frequency bin size depends on "settings.acqCohIntegration")
  numberOfFrqBins = ...
          round(settings.acqSearchBand * 2 * settings.acqCohIntegration) + 1;
  
  // Generate GLONASS ST code and sample it according to the sampling freq.
  stCodesTable = makeStTable(settings);
  // Copy vector stCodesTable settings.acqCohIntegration times.
  stCodesTable = repmat(stCodesTable, 1, settings.acqCohIntegration); 
  
  //--- Initialize arrays to speed up the code -------------------------------
  // Search results of all frequency bins and code shifts (for one satellite)
  results     = zeros(numberOfFrqBins, samplesPerCode);
  // Carrier frequencies of the frequency bins
  frqBins     = zeros(1, numberOfFrqBins);
  
//--- Initialize acqResults ------------------------------------------------
  // Carrier frequencies of detected signals
  acqResults.carrFreq     = zeros(1, 14);
  // ST code phases of detected signals
  acqResults.codePhase    = zeros(1, 14);
  // Correlation peak ratios of the detected signals
  acqResults.peakMetric   = zeros(1, 14);
  // GLONASS satellite frequency number
  acqResults.freqChannel  = zeros(1, 14);
  
  acqResultsIndx = 0; //index varibale for "acqResults"
  
  printf('(');
  
  // Perform search for all listed FCH numbers ...
  for FCH = settings.acqFCHList //FCH = frequency channel.
  
  // Correlate signals ======================================================   
    //--- Perform DFT of ST code ------------------------------------------
    stCodeFreqDom = conj(fft(stCodesTable(1, :)));
    
    //--- Make the correlation for whole frequency band (for all freq. bins)
    for frqBinIndex = 1:numberOfFrqBins
        //--- Generate carrier wave frequency grid (freqency step depends
        // on "settings.acqCohIntegration") --------------------------------
        frqBins(frqBinIndex) = (settings.IF + FCH*settings.L2_IF_step) - ...
                               (settings.acqSearchBand/2) * 1000 + ...
                               (1000 / (2*settings.acqCohIntegration)) *...
                               (frqBinIndex - 1);
        
        //--- Generate local sine and cosine -------------------------------
        sigCarr = exp(%i*frqBins(frqBinIndex) * phasePoints);
        
        //--- "Remove carrier" from the signal and Convert the baseband 
        // signal to frequency domain --------------------------------------
        IQfreqDom1 = fft(sigCarr .* signal1);
        IQfreqDom2 = fft(sigCarr .* signal2);
        
        //--- Multiplication in the frequency domain (correlation in time
        //domain)
        convCodeIQ1 = IQfreqDom1 .* stCodeFreqDom;
        convCodeIQ2 = IQfreqDom2 .* stCodeFreqDom;
        
        //--- Perform inverse DFT and store correlation results ------------
        acqRes1 = abs(ifft(convCodeIQ1)) .^ 2;
        acqRes2 = abs(ifft(convCodeIQ2)) .^ 2;
        
        //--- Check which msec had the greater power and save that, will
        //"blend" 1st and 2nd "settings.acqCohIntegration" msec but will
        // correct data bit issues
        if (max(acqRes1) > max(acqRes2))
            results(frqBinIndex, :) = acqRes1(1:samplesPerCode);//Only first
            // ms is important. The rest are copies of the first 1msec.
        else
            results(frqBinIndex, :) = acqRes2(1:samplesPerCode);//Only first
            // ms is important. The rest are copies of the first 1msec.
        end
        
    end // frqBinIndex = 1:numberOfFrqBins

// Look for correlation peaks in the results ==============================
    // Find the highest peak and compare it to the second highest peak
    // The second peak is chosen not closer than 1 chip to the highest peak
    
    //--- Find the correlation peak and the carrier frequency --------------
    [peakSize frequencyBinIndex] = max(max(results, 'c'));
    
    //--- Find code phase of the same correlation peak ---------------------
    [peakSize codePhase] = max(max(results, 'r'));
    
    //--- Find 1 chip wide ST code phase exclude range around the peak ----
    samplesPerCodeChip   = round(settings.samplingFreq /...
                                 settings.codeFreqBasis);
    excludeRangeIndex1 = codePhase - samplesPerCodeChip;
    excludeRangeIndex2 = codePhase + samplesPerCodeChip;

    //--- Correct ST code phase exclude range if the range includes array
    //boundaries
    if excludeRangeIndex1 < 2
        codePhaseRange = excludeRangeIndex2 : ...
                         (samplesPerCode + excludeRangeIndex1);
    
    elseif excludeRangeIndex2 >= samplesPerCode
        codePhaseRange = (excludeRangeIndex2 - samplesPerCode) : ...
                         excludeRangeIndex1;
    else
        codePhaseRange = [1:excludeRangeIndex1, ...
                          excludeRangeIndex2 : samplesPerCode];
    end
    
    //--- Find the second highest correlation peak in the same freq. bin ---
    secondPeakSize = max(results(frequencyBinIndex, codePhaseRange));
    
    //--- Store result -----------------------------------------------------
    acqResultsIndx = acqResultsIndx + 1;
    acqResults.peakMetric(acqResultsIndx) = peakSize/secondPeakSize;
    
    // If the result is above threshold, then there is a signal ...
    if (peakSize/secondPeakSize) > settings.acqThreshold
      //--- Indicate PRN number of the detected signal -------------------
      //printf('%02d ', FCH);
      printf('%02d ', (-FCH));
      acqResults.codePhase(acqResultsIndx)   = codePhase;
      acqResults.carrFreq(acqResultsIndx)    =...
                               (settings.IF + FCH*settings.L2_IF_step) - ...
                               (settings.acqSearchBand/2) * 1000 + ...
                               (1000 / (2*settings.acqCohIntegration)) *...
                               (frequencyBinIndex - 1);
      //acqResults.freqChannel(acqResultsIndx) = FCH;
      acqResults.freqChannel(acqResultsIndx) = (-FCH);//На L2 спектр перевернут!!! Особенность!!!
    else
      //--- No signal with this FCH --------------------------------------
      printf('. ');
    end   // if (peakSize/secondPeakSize) > settings.acqThreshold
    
  end    // for FCH = satelliteList

//=== Acquisition is over ==================================================
printf(')\n');

endfunction
