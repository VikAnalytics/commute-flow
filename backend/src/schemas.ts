import { z } from "zod";

const latSchema = z.number().min(-90).max(90);
const lngSchema = z.number().min(-180).max(180);

export const apartmentsSearchSchema = z.object({
  workplaceName: z.string().trim().min(3),
  workplaceLat: latSchema,
  workplaceLng: lngSchema,
  withinMiles: z.number().positive().max(50)
});

export const travelSearchSchema = z.object({
  cityName: z.string().trim().min(2),
  hubs: z
    .array(
      z.object({
        name: z.string().trim().min(1),
        lat: latSchema,
        lng: lngSchema
      })
    )
    .min(1)
    .max(10)
});
