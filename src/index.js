const express = require('express');
const dotenv = require('dotenv');
const equipmentRoutes = require('./routes/gearRoutes');

dotenv.config();
const app = express();
app.use(express.json());

app.use('/api/gear', equipmentRoutes);

// Load balancer
app.get('/', (req, res) => {
    res.json({status: 'modulr API is live...'});
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`modulr API running on port ${PORT}`);
});
