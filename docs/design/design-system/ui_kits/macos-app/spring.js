// Mola com velocidade preservada (WWDC23 "Animate with springs"): massa 1,
// rigidez = (2π/duração)², amortecimento = 4π(1−bounce)/duração. Interrompível: um novo alvo
// continua a partir da posição e da velocidade atuais.
(function () {
  const params = (duration, bounce) => ({
    k: Math.pow((2 * Math.PI) / duration, 2),
    c: bounce >= 0 ? (4 * Math.PI * (1 - bounce)) / duration : (4 * Math.PI) / (duration * (1 + bounce))
  });
  function useSpring(target, { duration = 0.5, bounce = 0, instant = false } = {}) {
    const [value, setValue] = React.useState(target);
    const st = React.useRef({ x: target, v: 0, raf: 0, last: 0 });
    React.useEffect(() => {
      const s = st.current;
      cancelAnimationFrame(s.raf);
      if (instant) { s.x = target; s.v = 0; setValue(target); return; }
      const { k, c } = params(duration, bounce);
      s.last = performance.now();
      const tick = now => {
        const dt = Math.min(0.032, (now - s.last) / 1000); s.last = now;
        const a = k * (target - s.x) - c * s.v;
        s.v += a * dt; s.x += s.v * dt;
        if (Math.abs(target - s.x) < 0.3 && Math.abs(s.v) < 2) { s.x = target; s.v = 0; setValue(target); return; }
        setValue(s.x); s.raf = requestAnimationFrame(tick);
      };
      s.raf = requestAnimationFrame(tick);
      return () => cancelAnimationFrame(s.raf);
    }, [target, duration, bounce, instant]);
    return value;
  }
  window.mbUseSpring = useSpring;
})();
