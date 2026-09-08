//! Anti-replay window for assertion counters.
//!
//! Every assertion carries a counter the Secure Enclave increments, so a
//! captured assertion can be rejected on its second use. A bare high-water mark
//! would do that, but it also rejects the older of two assertions that raced,
//! which happens whenever the app has two requests in flight. The window keeps
//! a high-water mark plus a bitmap of the 64 counters below it, accepting
//! out-of-order arrivals once each.

use super::AttestError;

/// How far below the high-water mark a counter may still arrive.
const WINDOW: u32 = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReplayWindow {
    high_water: u32,
    /// Bit `i` marks the counter `high_water - i` as already spent.
    mask: u64,
}

impl ReplayWindow {
    pub fn new(high_water: u32, mask: u64) -> Self {
        Self { high_water, mask }
    }

    pub fn high_water(self) -> u32 {
        self.high_water
    }

    pub fn mask(self) -> u64 {
        self.mask
    }

    /// SQLite has no unsigned integer, so the mask round-trips as the same 64
    /// bits reinterpreted rather than as a value that would not fit.
    pub fn from_storage(high_water: i64, mask: i64) -> Self {
        Self {
            high_water: high_water.clamp(0, u32::MAX as i64) as u32,
            mask: mask as u64,
        }
    }

    pub fn to_storage(self) -> (i64, i64) {
        (self.high_water as i64, self.mask as i64)
    }

    /// Records `counter` as spent, or reports why it cannot be.
    pub fn accept(&mut self, counter: u32) -> Result<(), AttestError> {
        if counter == 0 {
            return Err(AttestError::ReplayedCounter {
                counter,
                high_water: self.high_water,
            });
        }

        if counter > self.high_water {
            let shift = counter - self.high_water;
            self.mask = if shift >= WINDOW {
                1
            } else {
                (self.mask << shift) | 1
            };
            self.high_water = counter;
            return Ok(());
        }

        let age = self.high_water - counter;
        if age >= WINDOW || self.mask & (1u64 << age) != 0 {
            return Err(AttestError::ReplayedCounter {
                counter,
                high_water: self.high_water,
            });
        }
        self.mask |= 1u64 << age;
        Ok(())
    }
}

impl Default for ReplayWindow {
    fn default() -> Self {
        Self::new(0, 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_a_rising_counter() {
        let mut window = ReplayWindow::default();
        for counter in 1..=200 {
            window.accept(counter).expect("rising counter is fresh");
        }
        assert_eq!(window.high_water(), 200);
    }

    #[test]
    fn rejects_an_exact_replay() {
        let mut window = ReplayWindow::default();
        window.accept(7).unwrap();
        assert!(window.accept(7).is_err());
    }

    #[test]
    fn accepts_out_of_order_arrivals_once_each() {
        let mut window = ReplayWindow::default();
        window.accept(10).unwrap();
        window.accept(8).expect("a raced assertion still lands");
        assert!(window.accept(8).is_err(), "but only once");
        window.accept(9).expect("the gap is still open");
        assert_eq!(window.high_water(), 10);
    }

    #[test]
    fn rejects_counters_older_than_the_window() {
        let mut window = ReplayWindow::default();
        window.accept(1).unwrap();
        window.accept(100).unwrap();
        assert!(window.accept(35).is_err(), "100 - 35 is past the 64 window");
        window.accept(90).expect("within the window and unspent");
    }

    #[test]
    fn a_jump_past_the_window_clears_the_bitmap() {
        let mut window = ReplayWindow::default();
        window.accept(5).unwrap();
        window.accept(500).unwrap();
        assert_eq!(window.mask(), 1);
        assert!(window.accept(5).is_err());
    }

    #[test]
    fn rejects_counter_zero() {
        let mut window = ReplayWindow::default();
        assert!(window.accept(0).is_err(), "attestation owns counter 0");
    }

    #[test]
    fn survives_a_storage_round_trip() {
        let mut window = ReplayWindow::default();
        window.accept(20).unwrap();
        window.accept(18).unwrap();
        let (high_water, mask) = window.to_storage();
        let restored = ReplayWindow::from_storage(high_water, mask);
        assert_eq!(window, restored);
    }

    #[test]
    fn a_high_bit_mask_round_trips_through_signed_storage() {
        let window = ReplayWindow::new(64, 1u64 << 63);
        let (high_water, mask) = window.to_storage();
        assert!(mask < 0, "the top bit reads back as a negative i64");
        assert_eq!(ReplayWindow::from_storage(high_water, mask), window);
    }
}
