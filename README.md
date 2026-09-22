# Algorithmic Trading EA

A rule-based algorithmic trading system developed in **MQL5** for **MetaTrader 5**. The project explores automated trade execution, quantitative signal filtering, position sizing, and risk management on EUR/USD.

## Overview

The Expert Advisor (EA) analyzes market conditions and determines whether a trade satisfies a predefined set of technical and risk-management rules before execution.

Rather than relying on a single indicator, the system combines trend, momentum, volatility, price-action, and higher-timeframe information to filter potential trades.

The project is being developed iteratively, with each version used to test, debug, and refine the system.

## Core Features

- Automated EUR/USD trade execution
- EMA-based trend detection
- RSI momentum filtering
- ATR-based volatility analysis
- ADX trend-strength filtering
- Higher-timeframe trend confirmation
- Pullback and breakout detection
- Breakout/retest confirmation
- Dynamic position sizing
- Configurable stop-loss and reward-to-risk targets
- Break-even management
- ATR-based trailing stops
- Spread and slippage protection
- Trading-session restrictions
- Daily loss protection
- Maximum-trades-per-day controls
- Diagnostic logging for testing and debugging

## Risk Management

Risk controls are built directly into the execution logic. The EA can restrict position size based on account equity, limit daily losses, cap the number of trades taken per day, reject trades during unfavorable spread conditions, and manage open positions using break-even and trailing-stop logic.

These safeguards are designed to separate trade-signal generation from account-level risk management.

## Strategy Architecture

The system follows a general decision pipeline:

1. Read current and historical market data
2. Determine the broader market trend
3. Evaluate momentum and trend strength
4. Analyze volatility and price structure
5. Detect qualifying pullback or breakout conditions
6. Apply higher-timeframe confirmation
7. Check spread, session, and risk constraints
8. Calculate position size and protective levels
9. Execute qualifying trades
10. Manage open positions and record diagnostic information

## Technology

- **Language:** MQL5
- **Platform:** MetaTrader 5
- **Market:** EUR/USD
- **Primary timeframe:** M15
- **Development:** MetaEditor
- **Version control:** Git / GitHub

## Current Version

`v2.18`

Development is ongoing. The strategy is being iteratively tested and modified as weaknesses are identified through backtesting and debugging.

## What I Learned

Building this project has given me practical experience with:

- Rule-based system design
- Object-oriented/event-driven programming in MQL5
- Translating trading rules into programmatic logic
- Debugging and iterative software development
- Working with financial time-series data
- Algorithmic risk management
- Parameter configuration and experimentation
- Backtesting and evaluating automated systems

## Disclaimer

This project is an educational and software-development project. It is not financial advice, and no profitability or future-performance claims are made.
