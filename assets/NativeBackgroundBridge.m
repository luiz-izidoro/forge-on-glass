#import <Foundation/Foundation.h>
#import <BackgroundTasks/BackgroundTasks.h>

// O handler é registrado em Objective-C porque o perfil Swift do builder não
// carrega a interface Swift de BackgroundTasks. A tarefa só é concluída quando
// o código Swift chama radar_background_complete().
extern void radar_background_refresh_entry(void);
static BGTask *RadarActiveTask = nil;

void radar_register_background(void) {
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:@"com.minis.radar.refresh"
                                                         usingQueue:nil
                                                      launchHandler:^(__kindof BGTask *task) {
        RadarActiveTask = task;
        radar_background_refresh_entry();
    }];
}

void radar_schedule_background(void) {
    BGAppRefreshTaskRequest *request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:@"com.minis.radar.refresh"];
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:3600.0];
    [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:nil];
}

void radar_background_complete(BOOL success) {
    [RadarActiveTask setTaskCompletedWithSuccess:success];
    RadarActiveTask = nil;
    radar_schedule_background();
}
