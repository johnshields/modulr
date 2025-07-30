const express = require('express');
const router = express.Router();
const { getAllGear, getGearById } = require('../controllers/gearController');

router.get('/', getAllGear);
router.get('/:id', getGearById);

module.exports = router;
