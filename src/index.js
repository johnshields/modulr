const express = require('express');
const dotenv = require('dotenv');
const gearRoutes = require('./routes/gearRoutes');
const swaggerUi = require('swagger-ui-express');
const YAML = require('yamljs');
const swaggerDocument = YAML.load('./src/docs/swagger.yaml');

dotenv.config();
const app = express();
app.use(express.json());

// Swagger API docs
app.use('/api', swaggerUi.serve, (req, res, next) => swaggerUi.setup(swaggerDocument)(req, res, next));

// Route setup
app.use('/api/gear', gearRoutes);

// Load balancer
app.get('/', (req, res) => {
    res.json({status: 'modulr API is live...'});
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
    console.log(`modulr API running on port ${PORT}`);
});
