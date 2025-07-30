const express = require('express');
const dotenv = require('dotenv');
const { createClient } = require('@supabase/supabase-js');

dotenv.config();
const app = express();
app.use(express.json());

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ status: 'modulr API is live...' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`modulr API running on port ${PORT}`));
