// Quick test script to verify the new 3% fee calculation
// Run with: node test-fee-calculation.js

function calculateWithdrawalFee(payoutAmount) {
  if (payoutAmount < 0) {
    throw new Error('Invalid withdrawal amount');
  }

  // Simple 3% fee calculation
  const feePercentage = 0.03; // 3%
  const fee = Math.round(payoutAmount * feePercentage * 100) / 100; // Round to 2 decimals
  const walletDebit = payoutAmount + fee;
  const netPayout = payoutAmount; // User receives exactly what they requested

  return {
    fee,
    fee_percentage: 3,
    wallet_debit: walletDebit,
    net_payout: netPayout,
  };
}

// Test cases
const testCases = [
  { amount: 50, expected_fee: 1.50, expected_debit: 51.50 },
  { amount: 100, expected_fee: 3.00, expected_debit: 103.00 },
  { amount: 150, expected_fee: 4.50, expected_debit: 154.50 },
  { amount: 500, expected_fee: 15.00, expected_debit: 515.00 },
  { amount: 1000, expected_fee: 30.00, expected_debit: 1030.00 },
  { amount: 5000, expected_fee: 150.00, expected_debit: 5150.00 },
];

console.log('🧪 Testing 3% Fee Calculation\n');
console.log('═══════════════════════════════════════════════════════════');

let allPassed = true;

testCases.forEach((test, index) => {
  const result = calculateWithdrawalFee(test.amount);
  const feePassed = result.fee === test.expected_fee;
  const debitPassed = result.wallet_debit === test.expected_debit;
  const payoutPassed = result.net_payout === test.amount;
  const passed = feePassed && debitPassed && payoutPassed;
  
  if (!passed) allPassed = false;
  
  console.log(`\nTest ${index + 1}: ${passed ? '✅ PASS' : '❌ FAIL'}`);
  console.log(`  Payout Amount:    K${test.amount.toFixed(2)}`);
  console.log(`  Fee (3%):         K${result.fee.toFixed(2)} ${feePassed ? '✓' : '✗ Expected: K' + test.expected_fee.toFixed(2)}`);
  console.log(`  Wallet Debit:     K${result.wallet_debit.toFixed(2)} ${debitPassed ? '✓' : '✗ Expected: K' + test.expected_debit.toFixed(2)}`);
  console.log(`  Net Payout:       K${result.net_payout.toFixed(2)} ${payoutPassed ? '✓' : '✗ Expected: K' + test.amount.toFixed(2)}`);
});

console.log('\n═══════════════════════════════════════════════════════════');
console.log(`\n${allPassed ? '✅ All tests passed!' : '❌ Some tests failed!'}\n`);

// Example scenarios
console.log('\n📊 Example Scenarios:\n');

const scenarios = [
  { 
    name: 'Small withdrawal',
    payout: 50,
    wallet_balance: 100
  },
  { 
    name: 'Medium withdrawal',
    payout: 500,
    wallet_balance: 600
  },
  { 
    name: 'Large withdrawal',
    payout: 5000,
    wallet_balance: 5200
  },
  { 
    name: 'Insufficient balance',
    payout: 1000,
    wallet_balance: 500
  },
];

scenarios.forEach((scenario, index) => {
  const calc = calculateWithdrawalFee(scenario.payout);
  const hasEnough = scenario.wallet_balance >= calc.wallet_debit;
  
  console.log(`${index + 1}. ${scenario.name}:`);
  console.log(`   User wants:        K${scenario.payout.toFixed(2)}`);
  console.log(`   Platform fee (3%): K${calc.fee.toFixed(2)}`);
  console.log(`   Total needed:      K${calc.wallet_debit.toFixed(2)}`);
  console.log(`   Wallet balance:    K${scenario.wallet_balance.toFixed(2)}`);
  console.log(`   Status:            ${hasEnough ? '✅ Can withdraw' : '❌ Insufficient balance'}`);
  if (hasEnough) {
    console.log(`   User receives:     K${calc.net_payout.toFixed(2)}`);
  }
  console.log('');
});

console.log('═══════════════════════════════════════════════════════════\n');
