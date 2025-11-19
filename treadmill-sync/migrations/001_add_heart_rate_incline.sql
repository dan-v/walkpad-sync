-- Migration: Add heart rate and incline tracking
-- Date: 2025-11-19

-- Add heart_rate column to workout_samples
ALTER TABLE workout_samples ADD COLUMN heart_rate INTEGER; -- beats per minute

-- Add incline column to workout_samples
ALTER TABLE workout_samples ADD COLUMN incline REAL; -- percentage

-- Add average and max heart rate to workouts table
ALTER TABLE workouts ADD COLUMN avg_heart_rate REAL; -- bpm
ALTER TABLE workouts ADD COLUMN max_heart_rate INTEGER; -- bpm

-- Add average and max incline to workouts table
ALTER TABLE workouts ADD COLUMN avg_incline REAL; -- percentage
ALTER TABLE workouts ADD COLUMN max_incline REAL; -- percentage
