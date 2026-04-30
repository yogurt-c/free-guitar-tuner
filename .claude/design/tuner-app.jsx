// tuner-app.jsx — Guitar Tuner UI
// Dark, modern minimal aesthetic. Circular analog meter as primary viz.
// Horizontal string row + dropdown for tuning presets.

const { useState, useEffect, useRef, useMemo } = React;

// ─── Tuning presets ────────────────────────────────────────────────
// Each string: { note, octave, freq } — low to high
const PRESETS = {
  standard:  { name: 'Standard',         strings: [
    { note: 'E', octave: 2, freq: 82.41 },
    { note: 'A', octave: 2, freq: 110.00 },
    { note: 'D', octave: 3, freq: 146.83 },
    { note: 'G', octave: 3, freq: 196.00 },
    { note: 'B', octave: 3, freq: 246.94 },
    { note: 'E', octave: 4, freq: 329.63 },
  ]},
  dropD:     { name: 'Drop D',           strings: [
    { note: 'D', octave: 2, freq: 73.42 },
    { note: 'A', octave: 2, freq: 110.00 },
    { note: 'D', octave: 3, freq: 146.83 },
    { note: 'G', octave: 3, freq: 196.00 },
    { note: 'B', octave: 3, freq: 246.94 },
    { note: 'E', octave: 4, freq: 329.63 },
  ]},
  dropC:     { name: 'Drop C',           strings: [
    { note: 'C', octave: 2, freq: 65.41 },
    { note: 'G', octave: 2, freq: 98.00 },
    { note: 'C', octave: 3, freq: 130.81 },
    { note: 'F', octave: 3, freq: 174.61 },
    { note: 'A', octave: 3, freq: 220.00 },
    { note: 'D', octave: 4, freq: 293.66 },
  ]},
  halfStep:  { name: 'Half Step Down',   strings: [
    { note: 'E♭', octave: 2, freq: 77.78 },
    { note: 'A♭', octave: 2, freq: 103.83 },
    { note: 'D♭', octave: 3, freq: 138.59 },
    { note: 'G♭', octave: 3, freq: 185.00 },
    { note: 'B♭', octave: 3, freq: 233.08 },
    { note: 'E♭', octave: 4, freq: 311.13 },
  ]},
  openG:     { name: 'Open G',           strings: [
    { note: 'D', octave: 2, freq: 73.42 },
    { note: 'G', octave: 2, freq: 98.00 },
    { note: 'D', octave: 3, freq: 146.83 },
    { note: 'G', octave: 3, freq: 196.00 },
    { note: 'B', octave: 3, freq: 246.94 },
    { note: 'D', octave: 4, freq: 293.66 },
  ]},
  openD:     { name: 'Open D',           strings: [
    { note: 'D', octave: 2, freq: 73.42 },
    { note: 'A', octave: 2, freq: 110.00 },
    { note: 'D', octave: 3, freq: 146.83 },
    { note: 'F♯', octave: 3, freq: 185.00 },
    { note: 'A', octave: 3, freq: 220.00 },
    { note: 'D', octave: 4, freq: 293.66 },
  ]},
  dadgad:    { name: 'DADGAD',           strings: [
    { note: 'D', octave: 2, freq: 73.42 },
    { note: 'A', octave: 2, freq: 110.00 },
    { note: 'D', octave: 3, freq: 146.83 },
    { note: 'G', octave: 3, freq: 196.00 },
    { note: 'A', octave: 3, freq: 220.00 },
    { note: 'D', octave: 4, freq: 293.66 },
  ]},
};

const PRESET_KEYS = ['standard', 'dropD', 'dropC', 'halfStep', 'openG', 'openD', 'dadgad'];

// ─── Helpers ───────────────────────────────────────────────────────
const noteWithSharp = (n) => n.replace('♯', '#').replace('♭', 'b');

// ─── Theme ─────────────────────────────────────────────────────────
function getTheme(t) {
  const dark = t.theme === 'dark';
  return {
    dark,
    bg:        dark ? '#0B0B0E' : '#F4F2EE',
    surface:   dark ? '#15151A' : '#FFFFFF',
    surface2:  dark ? '#1F1F26' : '#EBE8E1',
    text:      dark ? '#F5F4F0' : '#15141A',
    textMuted: dark ? 'rgba(245,244,240,0.55)' : 'rgba(20,19,26,0.5)',
    textDim:   dark ? 'rgba(245,244,240,0.32)' : 'rgba(20,19,26,0.32)',
    line:      dark ? 'rgba(245,244,240,0.08)' : 'rgba(20,19,26,0.08)',
    accent:    t.accent,
    inTune:    t.inTuneColor,
    flat:      '#E0824A',  // warm — too low
    sharp:     '#5BA3E0',  // cool — too high
  };
}

// ─── Top bar (in-screen) ───────────────────────────────────────────
function TopBar(props) {
  const { theme, t, setTweak, onMenuClick } = props;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '54px 22px 8px',
    }}>
      <button onClick={onMenuClick} style={{
        width: 38, height: 38, borderRadius: 19, border: 'none',
        background: theme.surface2, color: theme.textMuted,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        cursor: 'pointer',
      }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <line x1="4" y1="6" x2="20" y2="6" />
          <line x1="4" y1="12" x2="14" y2="12" />
          <line x1="4" y1="18" x2="18" y2="18" />
        </svg>
      </button>
      <div style={{
        fontSize: 13, fontWeight: 600, letterSpacing: 1.5,
        textTransform: 'uppercase', color: theme.textMuted,
      }}>{props.modeLabel || 'Tuner'}</div>
      <button
        onClick={() => setTweak('theme', t.theme === 'dark' ? 'light' : 'dark')}
        style={{
          width: 38, height: 38, borderRadius: 19, border: 'none',
          background: theme.surface2, color: theme.textMuted,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer',
        }}>
        {theme.dark ? (
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" />
          </svg>
        ) : (
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
          </svg>
        )}
      </button>
    </div>
  );
}

// ─── Preset Dropdown ───────────────────────────────────────────────
function PresetDropdown({ theme, presetKey, onChange }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  const preset = PRESETS[presetKey];
  const noteString = preset.strings.map(s => s.note).join(' ');

  useEffect(() => {
    const handler = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    if (open) document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  return (
    <div ref={ref} style={{ position: 'relative', margin: '0 22px 24px' }}>
      <button
        onClick={() => setOpen(!open)}
        style={{
          width: '100%', padding: '14px 18px',
          background: theme.surface, border: `1px solid ${theme.line}`,
          borderRadius: 14, cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          textAlign: 'left',
        }}>
        <div>
          <div style={{
            fontSize: 10, fontWeight: 600, letterSpacing: 1.2,
            textTransform: 'uppercase', color: theme.textDim, marginBottom: 3,
          }}>Tuning Preset</div>
          <div style={{
            fontSize: 16, fontWeight: 600, color: theme.text,
            display: 'flex', alignItems: 'baseline', gap: 10,
          }}>
            {preset.name}
            <span style={{
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 12, fontWeight: 500, color: theme.textMuted,
              letterSpacing: 0.5,
            }}>{noteString}</span>
          </div>
        </div>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
             stroke={theme.textMuted} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"
             style={{ transition: 'transform 0.2s', transform: open ? 'rotate(180deg)' : 'none' }}>
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>
      {open && (
        <div style={{
          position: 'absolute', top: 'calc(100% + 6px)', left: 0, right: 0,
          background: theme.surface, border: `1px solid ${theme.line}`,
          borderRadius: 14, overflow: 'hidden', zIndex: 100,
          boxShadow: theme.dark ? '0 12px 32px rgba(0,0,0,0.6)' : '0 12px 32px rgba(0,0,0,0.12)',
        }}>
          {PRESET_KEYS.map((key, i) => {
            const p = PRESETS[key];
            const isActive = key === presetKey;
            return (
              <button
                key={key}
                onClick={() => { onChange(key); setOpen(false); }}
                style={{
                  width: '100%', padding: '12px 18px', border: 'none',
                  background: isActive ? theme.surface2 : 'transparent',
                  borderTop: i === 0 ? 'none' : `1px solid ${theme.line}`,
                  cursor: 'pointer', textAlign: 'left',
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                }}>
                <div>
                  <div style={{ fontSize: 15, fontWeight: 500, color: theme.text }}>{p.name}</div>
                  <div style={{
                    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
                    fontSize: 11, color: theme.textMuted, marginTop: 2, letterSpacing: 0.5,
                  }}>{p.strings.map(s => s.note).join(' ')}</div>
                </div>
                {isActive && (
                  <div style={{
                    width: 6, height: 6, borderRadius: 3, background: theme.accent,
                  }} />
                )}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ─── Bar Meter (spectrum-style horizontal bars) ────────────────────
// cents: -50 to +50, mapped to active bar position
function BarMeter({ theme, cents, targetNote, targetOctave, currentFreq, targetFreq, inTune, signalLevel }) {
  // 21 bars total — center bar = 0¢, ±10 bars = ±50¢
  const NUM_BARS = 21;
  const CENTER = 10; // index of center bar
  const clamped = Math.max(-50, Math.min(50, cents));
  // active bar index (float for smooth interpolation)
  const activePos = CENTER + (clamped / 50) * 10;

  // Status label
  const status = inTune ? 'IN TUNE' : cents < -3 ? 'TOO LOW · ♭' : cents > 3 ? 'TOO HIGH · ♯' : 'NEAR';

  const noteColor = inTune ? theme.inTune
                  : cents < -3 ? theme.flat
                  : cents > 3 ? theme.sharp
                  : theme.text;

  // Compute bar styling — bars have varying heights based on distance from active
  const bars = [];
  for (let i = 0; i < NUM_BARS; i++) {
    const distFromActive = Math.abs(i - activePos);
    const distFromCenter = Math.abs(i - CENTER);
    const isCenter = i === CENTER;
    const isActive = distFromActive < 1.2;
    const inActiveRegion = distFromActive < 3;

    // Height: peaks at activePos, falls off
    const peakHeight = 1 - Math.min(1, distFromActive / 3.5);
    const baseHeight = 0.28;
    const heightRatio = baseHeight + peakHeight * 0.72;

    // Color — when in tune, bathe ALL bars in the in-tune color for a clear "snap"
    let color;
    if (inTune) {
      color = theme.inTune;
    } else if (inActiveRegion) {
      if (activePos < CENTER) color = theme.flat;
      else color = theme.sharp;
    } else if (isCenter) {
      color = theme.textMuted;
    } else {
      color = theme.line;
    }

    // Opacity falls with distance from active. When in tune, all bars stay punchy.
    const opacity = inTune
      ? Math.max(0.45, 1 - distFromCenter * 0.05)
      : inActiveRegion
      ? 1 - distFromActive * 0.18
      : isCenter ? 1 : 0.55;

    bars.push({ i, heightRatio, color, opacity, isCenter, isActive });
  }

  const BAR_AREA_HEIGHT = 96;

  return (
    <div style={{
      position: 'relative', padding: '0 22px', margin: '8px auto 0',
    }}>
      {/* Status pill */}
      <div style={{
        textAlign: 'center', marginBottom: 12,
      }}>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 7,
          padding: '5px 12px', borderRadius: 999,
          background: inTune ? `${theme.inTune}1F` : theme.surface,
          border: `1px solid ${inTune ? `${theme.inTune}55` : theme.line}`,
          fontSize: 10, fontWeight: 700, letterSpacing: 1.4,
          color: inTune ? theme.inTune : theme.textMuted,
          textTransform: 'uppercase',
          transition: 'all 0.2s',
        }}>
          <span style={{
            width: 6, height: 6, borderRadius: 3,
            background: inTune ? theme.inTune : theme.flat,
            animation: 'tunerPulse 1.4s ease-in-out infinite',
          }} />
          {status}
        </span>
      </div>

      {/* Big note display */}
      <div style={{ textAlign: 'center', marginBottom: 18 }}>
        <div style={{
          fontSize: 96, fontWeight: 300, lineHeight: 1, letterSpacing: -4,
          color: noteColor, transition: 'color 0.2s',
          fontVariantNumeric: 'tabular-nums',
        }}>
          {targetNote}
          <span style={{
            fontSize: 32, fontWeight: 400, color: theme.textMuted,
            verticalAlign: 'super', marginLeft: 2,
          }}>{targetOctave}</span>
        </div>
        <div style={{
          fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
          fontSize: 12, color: theme.textMuted, marginTop: 6,
          fontVariantNumeric: 'tabular-nums',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}>
          <span>{currentFreq.toFixed(2)} Hz</span>
          <span style={{ color: theme.textDim }}>→</span>
          <span style={{ color: theme.textDim }}>{targetFreq.toFixed(2)} Hz</span>
        </div>
      </div>

      {/* Bar meter */}
      <div style={{
        position: 'relative',
        height: BAR_AREA_HEIGHT,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        gap: 3,
        padding: inTune ? '0' : '0',
      }}>
        {/* In-tune halo backdrop */}
        {inTune && (
          <div style={{
            position: 'absolute', inset: '-12px -8px',
            background: `radial-gradient(ellipse at center, ${theme.inTune}28 0%, ${theme.inTune}00 70%)`,
            pointerEvents: 'none', zIndex: 0,
            animation: 'tunerHaloIn 0.25s ease-out',
          }} />
        )}
        {/* center reference line — vertical hairline behind the bars */}
        <div style={{
          position: 'absolute', top: -4, bottom: -4,
          left: '50%', width: 1, transform: 'translateX(-0.5px)',
          background: inTune ? `${theme.inTune}66` : theme.line,
          transition: 'background 0.2s',
          zIndex: 0,
        }} />

        {bars.map((b) => (
          <div key={b.i} style={{
            flex: 1,
            height: `${b.heightRatio * 100}%`,
            background: b.color,
            opacity: b.opacity,
            borderRadius: 3,
            transition: 'height 0.16s cubic-bezier(0.4, 0, 0.2, 1), background 0.2s, opacity 0.2s',
            boxShadow: inTune
              ? `0 0 6px ${theme.inTune}80`
              : b.isActive ? `0 0 12px ${b.color}66` : 'none',
            zIndex: 1,
          }} />
        ))}

        {/* Lock indicator — appears centered above the bars when in tune */}
        {inTune && (
          <div style={{
            position: 'absolute',
            left: '50%', top: -6,
            transform: 'translate(-50%, -100%)',
            display: 'flex', alignItems: 'center', gap: 5,
            padding: '4px 9px',
            borderRadius: 999,
            background: theme.inTune,
            color: theme.dark ? '#0B0B0E' : '#fff',
            fontSize: 9, fontWeight: 700, letterSpacing: 1.2,
            textTransform: 'uppercase',
            boxShadow: `0 4px 12px ${theme.inTune}55`,
            animation: 'tunerLockIn 0.28s cubic-bezier(0.34, 1.56, 0.64, 1)',
            zIndex: 2,
            whiteSpace: 'nowrap',
          }}>
            <svg width="9" height="9" viewBox="0 0 12 12" fill="none">
              <path d="M2.5 6.5l2.5 2.5L9.5 3.5" stroke="currentColor"
                    strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Locked
          </div>
        )}
      </div>

      {/* Cent scale labels */}
      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        marginTop: 10,
        fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
        fontSize: 10, letterSpacing: 0.5,
        color: theme.textDim,
      }}>
        <span>−50¢</span>
        <span style={{
          fontSize: 13, fontWeight: 600,
          color: inTune ? theme.inTune
               : Math.abs(cents) < 8 ? theme.text
               : cents < 0 ? theme.flat : theme.sharp,
          fontVariantNumeric: 'tabular-nums',
          transition: 'color 0.2s',
        }}>
          {cents > 0.5 ? '+' : ''}{cents.toFixed(1)}¢
        </span>
        <span>+50¢</span>
      </div>
    </div>
  );
}

// ─── Fretboard / Strings Diagram ───────────────────────────────────
// Stylized guitar headstock + strings view. Strings are drawn thicker for low,
// thinner for high. The selected string highlights with accent + a glow tag.
function FretboardView({ theme, strings, selected, onSelect, autoMode, tunedSet }) {
  // strings are passed low → high (idx 0 = low E)
  // Display order: low at TOP (thickest), high at BOTTOM (thinnest) — like looking at the fretboard
  const ordered = strings.map((s, i) => ({ ...s, idx: i }));

  return (
    <div style={{
      margin: '0 22px',
      padding: '14px 0 10px',
      borderRadius: 16,
      background: theme.surface,
      border: `1px solid ${theme.line}`,
      position: 'relative',
      overflow: 'hidden',
    }}>
      {/* nut */}
      <div style={{
        position: 'absolute', left: 64, top: 14, bottom: 10, width: 3,
        background: theme.dark ? 'rgba(245,244,240,0.18)' : 'rgba(20,19,26,0.18)',
        borderRadius: 1,
      }} />
      {/* fret line at right */}
      <div style={{
        position: 'absolute', right: 14, top: 14, bottom: 10, width: 1,
        background: theme.line,
      }} />

      {ordered.map((s, displayIdx) => {
        const isSelected = s.idx === selected;
        const isTuned = tunedSet.has(s.idx);
        // thicker for low strings (low idx)
        const thickness = 1.2 + (strings.length - 1 - s.idx) * 0.45;

        return (
          <button
            key={s.idx}
            onClick={() => onSelect(s.idx)}
            disabled={autoMode}
            style={{
              position: 'relative',
              display: 'flex', alignItems: 'center',
              width: '100%', height: 26,
              border: 'none', background: 'transparent',
              cursor: autoMode ? 'default' : 'pointer',
              opacity: autoMode && !isSelected ? 0.55 : 1,
              padding: 0,
            }}>
            {/* String label pill (left side) */}
            <div style={{
              width: 52, marginLeft: 8, flexShrink: 0,
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
              height: 22, borderRadius: 11,
              background: isSelected ? theme.accent : 'transparent',
              border: isSelected ? 'none' : `1px solid ${theme.line}`,
              transition: 'background 0.15s',
            }}>
              <span style={{
                fontSize: 9, color: isSelected ? (theme.dark ? '#0B0B0E' : '#fff') : theme.textDim,
                fontFamily: 'ui-monospace, monospace', fontWeight: 600,
              }}>{s.idx + 1}</span>
              <span style={{
                fontSize: 13, fontWeight: 700,
                color: isSelected ? (theme.dark ? '#0B0B0E' : '#fff') : theme.text,
                letterSpacing: -0.3,
              }}>{s.note}</span>
            </div>

            {/* The string itself */}
            <div style={{
              flex: 1, position: 'relative', height: '100%',
              display: 'flex', alignItems: 'center',
              marginLeft: 4, marginRight: 14,
            }}>
              <div style={{
                width: '100%',
                height: thickness,
                background: isSelected
                  ? `linear-gradient(90deg, ${theme.accent} 0%, ${theme.accent} 70%, ${theme.accent}99 100%)`
                  : (theme.dark ? 'rgba(245,244,240,0.32)' : 'rgba(20,19,26,0.4)'),
                borderRadius: thickness,
                boxShadow: isSelected
                  ? `0 0 8px ${theme.accent}66`
                  : (theme.dark ? '0 1px 0 rgba(0,0,0,0.4)' : '0 1px 0 rgba(255,255,255,0.6)'),
                transition: 'all 0.18s',
              }} />
              {/* tuned check at right end */}
              {isTuned && (
                <div style={{
                  position: 'absolute', right: -2, top: '50%', transform: 'translateY(-50%)',
                  width: 14, height: 14, borderRadius: 7,
                  background: theme.inTune,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  boxShadow: `0 0 0 3px ${theme.surface}, 0 0 8px ${theme.inTune}80`,
                }}>
                  <svg width="8" height="8" viewBox="0 0 12 12" fill="none">
                    <path d="M2.5 6.5l2.5 2.5L9.5 3.5" stroke={theme.dark ? '#0B0B0E' : '#fff'}
                          strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </div>
              )}
            </div>
          </button>
        );
      })}
    </div>
  );
}

// ─── Footer (mode + reference, no listen button) ────────────────────
function BottomControls({ theme, autoMode, onModeToggle, refPitch }) {
  return (
    <div style={{
      padding: '14px 22px 42px', // bottom padding clears the iOS home indicator
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      fontSize: 12, color: theme.textMuted,
      borderTop: `1px solid ${theme.line}`,
    }}>
      <button
        onClick={onModeToggle}
        style={{
          background: 'transparent', border: 'none', cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: 8,
          color: theme.textMuted, padding: 0, fontSize: 12,
        }}>
        <span style={{
          width: 28, height: 16, borderRadius: 8,
          background: autoMode ? theme.accent : theme.surface2,
          position: 'relative', transition: 'all 0.15s',
          flexShrink: 0,
        }}>
          <span style={{
            position: 'absolute', top: 2, left: autoMode ? 14 : 2,
            width: 12, height: 12, borderRadius: 6,
            background: theme.dark ? '#fff' : (autoMode ? '#fff' : theme.textMuted),
            transition: 'left 0.15s',
            boxShadow: '0 1px 2px rgba(0,0,0,0.2)',
          }} />
        </span>
        <span style={{ fontWeight: 500 }}>Auto-detect</span>
      </button>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
      }}>
        <span style={{
          width: 6, height: 6, borderRadius: 3, background: theme.inTune,
          animation: 'tunerPulse 1.4s ease-in-out infinite',
        }} />
        <span style={{
          fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
          letterSpacing: 0.5,
        }}>Mic live · A = {refPitch} Hz</span>
      </div>
    </div>
  );
}

// ─── Main App ─────────────────────────────────────────────────────
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "dark",
  "accent": "#C8B273",
  "inTuneColor": "#7DD3A0",
  "refPitch": 440
}/*EDITMODE-END*/;

// ─── Side Menu Sheet ────────────────────────────────────────────────
function SideMenu({ theme, open, onClose, mode, onSelectMode }) {
  const items = [
    { key: 'tuner', label: 'Tuner', sub: 'Pitch detection', icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
        <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
        <line x1="12" y1="19" x2="12" y2="23"/>
        <line x1="8" y1="23" x2="16" y2="23"/>
      </svg>
    )},
    { key: 'metronome', label: 'Metronome', sub: 'Tempo & beats', icon: (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 21l4-18h4l4 18z"/>
        <line x1="6" y1="21" x2="18" y2="21"/>
        <line x1="12" y1="6" x2="15" y2="15"/>
      </svg>
    )},
  ];
  return (
    <>
      {/* Backdrop */}
      <div onClick={onClose} style={{
        position: 'absolute', inset: 0, zIndex: 90,
        background: 'rgba(0,0,0,0.45)',
        opacity: open ? 1 : 0,
        pointerEvents: open ? 'auto' : 'none',
        transition: 'opacity 0.2s',
      }} />
      {/* Sheet */}
      <div style={{
        position: 'absolute', top: 0, bottom: 0, left: 0, width: 280,
        background: theme.bg, zIndex: 91,
        transform: open ? 'translateX(0)' : 'translateX(-100%)',
        transition: 'transform 0.25s cubic-bezier(0.4, 0, 0.2, 1)',
        boxShadow: '4px 0 30px rgba(0,0,0,0.4)',
        display: 'flex', flexDirection: 'column',
        padding: '60px 0 24px',
      }}>
        <div style={{
          padding: '0 22px 22px',
          fontSize: 11, fontWeight: 700, letterSpacing: 1.6, textTransform: 'uppercase',
          color: theme.textDim,
        }}>Tools</div>
        {items.map(item => {
          const active = mode === item.key;
          return (
            <button key={item.key}
              onClick={() => { onSelectMode(item.key); onClose(); }}
              style={{
                display: 'flex', alignItems: 'center', gap: 14,
                padding: '14px 22px',
                background: active ? (theme.dark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.04)') : 'transparent',
                border: 'none', cursor: 'pointer', textAlign: 'left',
                position: 'relative',
              }}>
              {active && <div style={{
                position: 'absolute', left: 0, top: 8, bottom: 8, width: 3,
                background: theme.accent, borderRadius: '0 2px 2px 0',
              }} />}
              <div style={{
                width: 36, height: 36, borderRadius: 10,
                background: active ? theme.accent + '22' : theme.surface2,
                color: active ? theme.accent : theme.textMuted,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>{item.icon}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 600, color: theme.text }}>{item.label}</div>
                <div style={{ fontSize: 11, color: theme.textMuted, marginTop: 1 }}>{item.sub}</div>
              </div>
            </button>
          );
        })}
      </div>
    </>
  );
}

// ─── Metronome screen ─────────────────────────────────────────
function MetronomeScreen({ theme }) {
  const [bpm, setBpm] = useState(96);
  const [playing, setPlaying] = useState(true);
  const [beatsPerBar, setBeatsPerBar] = useState(4);
  const [currentBeat, setCurrentBeat] = useState(0);

  useEffect(() => {
    if (!playing) return;
    const interval = 60000 / bpm;
    const id = setInterval(() => {
      setCurrentBeat(b => (b + 1) % beatsPerBar);
    }, interval);
    return () => clearInterval(id);
  }, [bpm, playing, beatsPerBar]);

  const tempoName = bpm < 60 ? 'Largo' : bpm < 76 ? 'Adagio' : bpm < 108 ? 'Andante' : bpm < 120 ? 'Moderato' : bpm < 156 ? 'Allegro' : 'Presto';

  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      padding: '20px 22px 0',
    }}>
      {/* Tempo display */}
      <div style={{ textAlign: 'center', marginTop: 28 }}>
        <div style={{
          fontSize: 11, fontWeight: 700, letterSpacing: 1.5, textTransform: 'uppercase',
          color: theme.textMuted, marginBottom: 4,
        }}>{tempoName}</div>
        <div style={{
          fontSize: 124, fontWeight: 200, lineHeight: 1, letterSpacing: -6,
          color: theme.text, fontVariantNumeric: 'tabular-nums',
        }}>{bpm}</div>
        <div style={{
          fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
          fontSize: 12, color: theme.textMuted, letterSpacing: 1.2, marginTop: 2,
        }}>BPM</div>
      </div>

      {/* Beat dots */}
      <div style={{
        display: 'flex', justifyContent: 'center', gap: 12,
        marginTop: 36,
      }}>
        {Array.from({ length: beatsPerBar }).map((_, i) => {
          const isActive = i === currentBeat && playing;
          const isDownbeat = i === 0;
          return (
            <div key={i} style={{
              width: isDownbeat ? 14 : 12, height: isDownbeat ? 14 : 12,
              borderRadius: 7,
              background: isActive ? (isDownbeat ? theme.accent : theme.text)
                                   : (theme.dark ? 'rgba(245,244,240,0.18)' : 'rgba(20,19,26,0.15)'),
              transform: isActive ? 'scale(1.3)' : 'scale(1)',
              transition: 'all 0.08s ease-out',
              boxShadow: isActive ? `0 0 12px ${isDownbeat ? theme.accent : theme.text}66` : 'none',
            }} />
          );
        })}
      </div>

      {/* BPM slider */}
      <div style={{ marginTop: 40 }}>
        <input type="range" min={40} max={220} value={bpm}
          onChange={(e) => setBpm(Number(e.target.value))}
          style={{ width: '100%', accentColor: theme.accent }} />
        <div style={{
          display: 'flex', justifyContent: 'space-between', marginTop: 8,
          fontFamily: 'ui-monospace, monospace', fontSize: 10, color: theme.textDim,
        }}>
          <span>40</span><span>220</span>
        </div>
      </div>

      {/* +/- and time signature row */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        gap: 12, marginTop: 20,
      }}>
        <button onClick={() => setBpm(b => Math.max(40, b - 1))} style={{
          width: 44, height: 44, borderRadius: 22, border: `1px solid ${theme.line}`,
          background: theme.surface, color: theme.text, fontSize: 22, cursor: 'pointer',
        }}>−</button>
        <div style={{
          flex: 1, display: 'flex', justifyContent: 'center', gap: 6,
        }}>
          {[3, 4, 6, 8].map(n => (
            <button key={n} onClick={() => { setBeatsPerBar(n); setCurrentBeat(0); }}
              style={{
                width: 38, height: 38, borderRadius: 10,
                border: 'none',
                background: beatsPerBar === n ? theme.accent : theme.surface,
                color: beatsPerBar === n ? (theme.dark ? '#0B0B0E' : '#fff') : theme.textMuted,
                fontWeight: 600, fontSize: 13, cursor: 'pointer',
                fontFamily: 'ui-monospace, monospace',
              }}>{n}/4</button>
          ))}
        </div>
        <button onClick={() => setBpm(b => Math.min(220, b + 1))} style={{
          width: 44, height: 44, borderRadius: 22, border: `1px solid ${theme.line}`,
          background: theme.surface, color: theme.text, fontSize: 22, cursor: 'pointer',
        }}>+</button>
      </div>

      <div style={{ flex: 1 }} />

      {/* Play/Pause */}
      <button onClick={() => { setPlaying(p => !p); setCurrentBeat(0); }}
        style={{
          width: '100%', height: 56, borderRadius: 28, border: 'none',
          background: playing ? theme.accent : (theme.dark ? '#fff' : '#15141A'),
          color: playing ? (theme.dark ? '#0B0B0E' : '#fff') : (theme.dark ? '#0B0B0E' : '#fff'),
          fontSize: 15, fontWeight: 600, letterSpacing: 0.4, cursor: 'pointer',
          marginBottom: 42, // clear iOS home indicator
        }}>
        {playing ? 'Stop' : 'Start'}
      </button>
    </div>
  );
}

function TunerApp() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const theme = getTheme(t);

  const [mode, setMode] = useState('tuner');
  const [menuOpen, setMenuOpen] = useState(false);
  const [presetKey, setPresetKey] = useState('standard');
  const preset = PRESETS[presetKey];
  const strings = preset.strings;

  const [selectedString, setSelectedString] = useState(0);
  const [autoMode, setAutoMode] = useState(false);

  // Simulated detected frequency — always live (no listen button)
  const [detectedFreq, setDetectedFreq] = useState(strings[0].freq);
  const [tunedSet, setTunedSet] = useState(new Set());

  const target = strings[selectedString];

  // Reset tuned set when preset changes
  useEffect(() => {
    setTunedSet(new Set());
    setSelectedString(0);
  }, [presetKey]);

  // Reset detected freq when target changes
  useEffect(() => {
    setDetectedFreq(target.freq * (0.965 + Math.random() * 0.07));
  }, [selectedString, presetKey]);

  // Simulate live mic input — cycles through realistic states so all
  // visualization states (low / near / in-tune / drift) are demonstrated.
  useEffect(() => {
    let raf;
    let phase = 0;
    let cycleStart = Date.now();
    const tick = () => {
      phase += 0.04;
      const elapsed = (Date.now() - cycleStart) / 1000;
      // 8s cycle: 0-2s low, 2-4s rising near, 4-6.5s LOCKED in tune, 6.5-8s drift
      let targetOffsetCents;
      let noiseAmp;
      if (elapsed < 2) {
        targetOffsetCents = -22 + Math.sin(elapsed * 1.5) * 4;
        noiseAmp = 0.25;
      } else if (elapsed < 4) {
        targetOffsetCents = -22 + ((elapsed - 2) / 2) * 22; // ramp to 0
        noiseAmp = 0.18;
      } else if (elapsed < 6.5) {
        targetOffsetCents = Math.sin(elapsed * 2) * 0.8; // tight wobble inside ±3¢
        noiseAmp = 0.04;
      } else {
        targetOffsetCents = ((elapsed - 6.5) / 1.5) * 14; // drift sharp
        noiseAmp = 0.18;
      }
      if (elapsed > 8) cycleStart = Date.now();

      const targetFreqShifted = target.freq * Math.pow(2, targetOffsetCents / 1200);
      setDetectedFreq(prev => {
        const drift = (targetFreqShifted - prev) * 0.18;
        const wobble = (Math.sin(phase * 1.7) * 0.4 + (Math.random() - 0.5)) * noiseAmp;
        return prev + drift + wobble;
      });
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [target.freq]);

  // Auto-mode: pick string closest to detected freq
  useEffect(() => {
    if (!autoMode) return;
    let best = 0, bestDist = Infinity;
    strings.forEach((s, i) => {
      const dist = Math.abs(1200 * Math.log2(detectedFreq / s.freq));
      if (dist < bestDist) { bestDist = dist; best = i; }
    });
    if (best !== selectedString && bestDist < 200) setSelectedString(best);
  }, [autoMode, detectedFreq, strings]);

  // Compute cents off (always live)
  const cents = 1200 * Math.log2(detectedFreq / target.freq);
  const inTune = Math.abs(cents) < 3;

  // Track tuned-state — only register a string as "tuned" after holding for ~0.6s
  const inTuneSinceRef = useRef(null);
  useEffect(() => {
    if (inTune) {
      if (inTuneSinceRef.current == null) inTuneSinceRef.current = Date.now();
      const elapsed = Date.now() - inTuneSinceRef.current;
      if (elapsed > 500) {
        setTunedSet(prev => {
          if (prev.has(selectedString)) return prev;
          const next = new Set(prev);
          next.add(selectedString);
          return next;
        });
      }
    } else {
      inTuneSinceRef.current = null;
    }
  }, [inTune, cents, selectedString]);

  const screen = (
    <div style={{
      width: '100%', height: '100%', background: theme.bg, color: theme.text,
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: '-apple-system, "SF Pro Text", "Inter", system-ui, sans-serif',
    }}>
      <style>{`
        @keyframes tunerPulse {
          0%,100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.4; transform: scale(0.7); }
        }
        @keyframes tunerLockIn {
          0% { opacity: 0; transform: translate(-50%, -80%) scale(0.7); }
          100% { opacity: 1; transform: translate(-50%, -100%) scale(1); }
        }
        @keyframes tunerHaloIn {
          0% { opacity: 0; }
          100% { opacity: 1; }
        }
      `}</style>
      <SideMenu theme={theme} open={menuOpen} onClose={() => setMenuOpen(false)}
                mode={mode} onSelectMode={setMode} />
      <TopBar theme={theme} t={t} setTweak={setTweak}
              onMenuClick={() => setMenuOpen(true)}
              modeLabel={mode === 'metronome' ? 'Metronome' : 'Tuner'} />

      {mode === 'metronome' ? (
        <MetronomeScreen theme={theme} />
      ) : (
      <>
      {/* Meter (bar style) */}
      <div style={{ marginTop: 18 }}>
        <BarMeter
          theme={theme}
          cents={cents}
          targetNote={target.note}
          targetOctave={target.octave}
          currentFreq={detectedFreq}
          targetFreq={target.freq}
          inTune={inTune}
        />
      </div>

      {/* Preset dropdown */}
      <div style={{ marginTop: 28 }}>
        <PresetDropdown theme={theme} presetKey={presetKey} onChange={setPresetKey} />
      </div>

      {/* Strings diagram */}
      <FretboardView
        theme={theme}
        strings={strings}
        selected={selectedString}
        onSelect={setSelectedString}
        autoMode={autoMode}
        tunedSet={tunedSet}
      />

      <div style={{ flex: 1 }} />
      <BottomControls
        theme={theme}
        autoMode={autoMode}
        onModeToggle={() => setAutoMode(a => !a)}
        refPitch={t.refPitch}
      />
      </>
      )}
    </div>
  );

  return (
    <>
      <div style={{
        minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: theme.dark ? '#08070A' : '#E8E5DE',
        padding: 32, boxSizing: 'border-box',
        fontFamily: '-apple-system, "SF Pro Text", system-ui, sans-serif',
      }}>
        <IOSDevice dark={theme.dark} width={390} height={844}>
          {screen}
        </IOSDevice>
      </div>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Theme" />
        <TweakRadio
          label="Mode"
          value={t.theme}
          options={[{ value: 'dark', label: 'Dark' }, { value: 'light', label: 'Light' }]}
          onChange={(v) => setTweak('theme', v)}
        />
        <TweakColor label="Accent" value={t.accent} onChange={(v) => setTweak('accent', v)} />
        <TweakColor label="In-tune color" value={t.inTuneColor} onChange={(v) => setTweak('inTuneColor', v)} />
        <TweakSection label="Reference" />
        <TweakSlider
          label="A pitch" value={t.refPitch} min={430} max={446} step={1} unit=" Hz"
          onChange={(v) => setTweak('refPitch', v)}
        />
      </TweaksPanel>
    </>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<TunerApp />);
