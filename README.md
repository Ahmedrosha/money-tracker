# Money Tracker

Personal Android money tracker built with Flutter.

## Features (v0.1)
- Accounts: cash, bank, savings, credit card, investment, other — each in its own currency
- Expense / income transactions with category, payee, date & time, note
- Transfers between accounts, including between different currencies
- Multi-currency: online exchange rates (auto-refresh every 12h), manual overrides
- Net worth and monthly totals in your main currency
- Running balance per account

## Getting the APK
Every push to `main` builds the app on GitHub Actions.
Download the APK from the **Releases** page (or the run's artifacts) and install it.
All builds use the same signing key (`ci/debug.keystore`), so new versions install over old ones and keep your data.

## Roadmap
1. ✅ Accounts, transactions, transfers, multi-currency
1b. ✅ Banks, installments, recurring items, calendar (v0.2)
2. Credit cards: limit, statement day, due date, installments (up to 24 months)
3. Assets: stocks & crypto holdings with prices
4. Import from Home Budget (Excel)
5. Reports & charts
